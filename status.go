package main

import (
	"encoding/json"
	"net/http"
	"time"
)

type statusResponse struct {
	Resolver bool `json:"resolver"`
	IPFS     bool `json:"ipfs"`
}

// checkIPFS быстро проверяет, отвечает ли локальный IPFS-шлюз — с коротким
// таймаутом, чтобы статус-запрос от расширения никогда не подвисал.
func checkIPFS() bool {
	client := &http.Client{Timeout: 1 * time.Second}
	resp, err := client.Get(cfg.IPFSGateway)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return true
}

// handleStatus — лёгкий health-check для расширения браузера (индикатор
// "работает/не работает"). Разрешаем CORS с любого origin: тут нет ничего
// чувствительного, только два булевых флага.
func handleStatus(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(statusResponse{
		Resolver: true,
		IPFS:     checkIPFS(),
	})
}
