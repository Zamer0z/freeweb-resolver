package main

import (
	"flag"
	"strings"
	"time"
)

type Config struct {
	DNSListen   string
	HTTPListen  string
	HTTPSListen string
	Upstream    string
	Zones       []string
	EthRPC      string
	IPFSGateway string
	IPFSAPI     string
	CADir       string
	DropToUser  string
	EnsCacheTTL time.Duration
	Seed        []string
}

var cfg Config

func parseFlags() {
	dnsListen := flag.String("dns-listen", "127.0.0.1:15353", "адрес, на котором слушает локальный DNS-резолвер")
	httpListen := flag.String("http-listen", "127.0.0.1:15380", "адрес HTTP-шлюза")
	httpsListen := flag.String("https-listen", "127.0.0.1:15443", "адрес HTTPS-шлюза")
	upstream := flag.String("upstream-dns", "1.1.1.1:53", "куда пересылать обычные (не перехваченные) DNS-запросы")
	zones := flag.String("zones", "test.,eth.", "перехватываемые зоны через запятую, с точкой на конце (например test.,eth.)")
	ethRPC := flag.String("eth-rpc", "https://ethereum-rpc.publicnode.com", "JSON-RPC эндпоинт Ethereum для резолвинга ENS")
	ipfsGateway := flag.String("ipfs-gateway", "http://127.0.0.1:8080", "адрес локального IPFS-шлюза (kubo)")
	ipfsAPI := flag.String("ipfs-api", "http://127.0.0.1:5001", "адрес RPC API локальной IPFS-ноды (нужен только для --seed)")
	caDir := flag.String("ca-dir", "ca", "директория для хранения локального CA (сертификат + приватный ключ)")
	dropToUser := flag.String("drop-to-user", "", "если запущено от root (нужно для портов <1024) — после бинда портов сбросить привилегии до этого пользователя")
	ensCacheTTL := flag.Duration("ens-cache-ttl", 5*time.Minute, "на сколько кешировать contenthash от ENS перед повторным походом в Ethereum")
	seed := flag.String("seed", "", "через запятую: .eth-имена чужих сайтов, которые эта нода добровольно и бесплатно тоже будет раздавать (пин на своей IPFS-ноде)")

	flag.Parse()

	cfg = Config{
		DNSListen:   *dnsListen,
		HTTPListen:  *httpListen,
		HTTPSListen: *httpsListen,
		Upstream:    *upstream,
		Zones:       splitList(*zones),
		EthRPC:      *ethRPC,
		IPFSGateway: *ipfsGateway,
		IPFSAPI:     *ipfsAPI,
		CADir:       *caDir,
		DropToUser:  *dropToUser,
		EnsCacheTTL: *ensCacheTTL,
		Seed:        splitList(*seed),
	}
}

func splitList(raw string) []string {
	parts := strings.Split(raw, ",")
	zones := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			zones = append(zones, p)
		}
	}
	return zones
}
