package main

import (
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/miekg/dns"
)

func isIntercepted(name string) bool {
	name = strings.ToLower(name)
	for _, zone := range cfg.Zones {
		if strings.HasSuffix(name, zone) {
			return true
		}
	}
	return false
}

func handleRequest(w dns.ResponseWriter, r *dns.Msg) {
	if len(r.Question) > 0 && isIntercepted(r.Question[0].Name) {
		handleIntercepted(w, r)
		return
	}
	handleForwarded(w, r)
}

func handleIntercepted(w dns.ResponseWriter, r *dns.Msg) {
	q := r.Question[0]
	msg := new(dns.Msg)
	msg.SetReply(r)
	msg.Authoritative = true

	if q.Qtype == dns.TypeA {
		rr, err := dns.NewRR(fmt.Sprintf("%s 60 IN A 127.0.0.1", q.Name))
		if err == nil {
			msg.Answer = append(msg.Answer, rr)
		}
	}

	if err := w.WriteMsg(msg); err != nil {
		log.Printf("write error for %s: %v", q.Name, err)
	}
}

func handleForwarded(w dns.ResponseWriter, r *dns.Msg) {
	client := &dns.Client{Timeout: 5 * time.Second}

	resp, _, err := client.Exchange(r, cfg.Upstream)
	if err != nil {
		log.Printf("upstream error for %s: %v", questionName(r), err)
		dns.HandleFailed(w, r)
		return
	}

	if err := w.WriteMsg(resp); err != nil {
		log.Printf("write error for %s: %v", questionName(r), err)
	}
}

func questionName(r *dns.Msg) string {
	if len(r.Question) == 0 {
		return "?"
	}
	return r.Question[0].Name
}

func newMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/_freeweb/status", handleStatus)
	mux.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		host, _, err := net.SplitHostPort(req.Host)
		if err != nil {
			host = req.Host
		}

		// Абсолютные пути вида /ipfs/<cid>/... — это подресурсы (JS/CSS/картинки),
		// которые сама страница запросила у "своего" origin; проксируем как есть.
		if strings.HasPrefix(req.URL.Path, "/ipfs/") || strings.HasPrefix(req.URL.Path, "/ipns/") {
			proxyIPFS(w, req.URL.Path)
			return
		}

		if strings.HasSuffix(host, ".eth") {
			contenthash, err := resolveENS(host)
			if err != nil {
				http.Error(w, fmt.Sprintf("ENS-резолвинг %s не удался: %v", host, err), http.StatusBadGateway)
				return
			}
			proxyIPFS(w, contenthash+req.URL.Path)
			return
		}

		fmt.Fprintf(w, "freeweb-resolver: привет с локального шлюза! (схема: %s)\nЗапрошенный домен (Host-заголовок): %s\n", req.URL.Scheme, host)
	})
	return mux
}

// bindListeners открывает все сокеты, включая, возможно, привилегированные
// порты <1024 — это единственная операция во всей программе, ради которой
// вообще может понадобиться root. Выполняется ДО dropPrivileges.
func bindListeners() (udpConn net.PacketConn, tcpListener, httpListener, httpsListener net.Listener) {
	var err error

	udpConn, err = net.ListenPacket("udp", cfg.DNSListen)
	if err != nil {
		log.Fatalf("bind DNS/udp %s: %v", cfg.DNSListen, err)
	}

	tcpListener, err = net.Listen("tcp", cfg.DNSListen)
	if err != nil {
		log.Fatalf("bind DNS/tcp %s: %v", cfg.DNSListen, err)
	}

	httpListener, err = net.Listen("tcp", cfg.HTTPListen)
	if err != nil {
		log.Fatalf("bind HTTP %s: %v", cfg.HTTPListen, err)
	}

	httpsListener, err = net.Listen("tcp", cfg.HTTPSListen)
	if err != nil {
		log.Fatalf("bind HTTPS %s: %v", cfg.HTTPSListen, err)
	}

	return udpConn, tcpListener, httpListener, httpsListener
}

func main() {
	parseFlags()

	// 1. Биндим все порты первыми, пока ещё есть root (если он вообще есть).
	udpConn, dnsTCPListener, httpListener, httpsListener := bindListeners()

	// 2. Сразу после бинда — сбрасываем привилегии. Дальше по коду ничего
	// не требует root, вся обработка чужих запросов идёт от обычного юзера.
	if err := dropPrivileges(cfg.DropToUser); err != nil {
		log.Fatalf("privilege drop failed: %v", err)
	}
	if isElevated() {
		log.Printf("WARNING: работаем от root (--drop-to-user не задан) — это небезопасно, задай флаг")
	}

	// 3. Обычная инициализация — уже без повышенных прав.
	cm, err := newCertManager()
	if err != nil {
		log.Fatalf("cert manager init failed: %v", err)
	}

	dns.HandleFunc(".", handleRequest)

	udpServer := &dns.Server{PacketConn: udpConn, Net: "udp"}
	tcpServer := &dns.Server{Listener: dnsTCPListener, Net: "tcp"}

	go func() {
		log.Printf("UDP listening on %s (intercepting: %v, forwarding rest to %s)", cfg.DNSListen, cfg.Zones, cfg.Upstream)
		if err := udpServer.ActivateAndServe(); err != nil {
			log.Fatalf("udp server failed: %v", err)
		}
	}()

	go func() {
		log.Printf("TCP listening on %s", cfg.DNSListen)
		if err := tcpServer.ActivateAndServe(); err != nil {
			log.Fatalf("tcp server failed: %v", err)
		}
	}()

	mux := newMux()

	go func() {
		log.Printf("HTTP listening on %s", cfg.HTTPListen)
		if err := http.Serve(httpListener, mux); err != nil {
			log.Fatalf("http server failed: %v", err)
		}
	}()

	tlsConfig := &tls.Config{GetCertificate: cm.GetCertificate}
	tlsListener := tls.NewListener(httpsListener, tlsConfig)
	httpsServer := &http.Server{Handler: mux, TLSConfig: tlsConfig}

	log.Printf("HTTPS listening on %s (local CA: %s/ca.crt)", cfg.HTTPSListen, cfg.CADir)
	if err := httpsServer.Serve(tlsListener); err != nil {
		log.Fatalf("https server failed: %v", err)
	}
}
