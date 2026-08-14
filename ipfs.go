package main

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

var ipfsHTTPClient = &http.Client{Timeout: 30 * time.Second}

// proxyIPFS забирает контент по contenthash (вида "/ipfs/<cid>" или
// "/ipns/<key>", как возвращает ens.ContenthashToString) с локальной
// IPFS-ноды и проксирует его напрямую в ответ клиенту.
func proxyIPFS(w http.ResponseWriter, contenthash string) {
	if !strings.HasPrefix(contenthash, "/ipfs/") && !strings.HasPrefix(contenthash, "/ipns/") {
		http.Error(w, fmt.Sprintf("неподдерживаемый тип contenthash: %s", contenthash), http.StatusBadGateway)
		return
	}

	targetURL := cfg.IPFSGateway + contenthash
	resp, err := ipfsHTTPClient.Get(targetURL)
	if err != nil {
		http.Error(w, fmt.Sprintf("не удалось получить контент с локальной IPFS-ноды: %v", err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	for key, values := range resp.Header {
		for _, v := range values {
			w.Header().Add(key, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}
