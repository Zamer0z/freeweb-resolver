package main

import (
	"fmt"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/ethclient"
	ens "github.com/wealdtech/go-ens/v3"
)

type ensCacheEntry struct {
	contenthash string
	expiresAt   time.Time
}

var (
	ensClientOnce sync.Once
	ensClient     *ethclient.Client
	ensClientErr  error

	ensCacheMu sync.Mutex
	ensCache   = make(map[string]ensCacheEntry)
)

func getEthClient() (*ethclient.Client, error) {
	ensClientOnce.Do(func() {
		ensClient, ensClientErr = ethclient.Dial(cfg.EthRPC)
	})
	return ensClient, ensClientErr
}

// resolveENS резолвит ENS-имя в contenthash. Результат кешируется на
// cfg.EnsCacheTTL: contenthash сайта меняется редко, а без кеша каждый
// заход на .eth-сайт означал бы новый поход в Ethereum на каждый клик —
// это и медленнее для пользователя, и лишняя нагрузка на чужой RPC.
func resolveENS(name string) (contenthash string, err error) {
	ensCacheMu.Lock()
	if entry, ok := ensCache[name]; ok && time.Now().Before(entry.expiresAt) {
		ensCacheMu.Unlock()
		return entry.contenthash, nil
	}
	ensCacheMu.Unlock()

	client, err := getEthClient()
	if err != nil {
		return "", fmt.Errorf("подключение к RPC: %w", err)
	}

	resolver, err := ens.NewResolver(client, name)
	if err != nil {
		return "", fmt.Errorf("резолвер для %s: %w", name, err)
	}

	raw, err := resolver.Contenthash()
	if err != nil {
		return "", fmt.Errorf("contenthash для %s: %w", name, err)
	}

	str, err := ens.ContenthashToString(raw)
	if err != nil {
		return "", fmt.Errorf("декодирование contenthash: %w", err)
	}

	ensCacheMu.Lock()
	ensCache[name] = ensCacheEntry{contenthash: str, expiresAt: time.Now().Add(cfg.EnsCacheTTL)}
	ensCacheMu.Unlock()

	return str, nil
}
