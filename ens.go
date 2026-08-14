package main

import (
	"fmt"

	"github.com/ethereum/go-ethereum/ethclient"
	ens "github.com/wealdtech/go-ens/v3"
)

func resolveENS(name string) (contenthash string, err error) {
	client, err := ethclient.Dial(cfg.EthRPC)
	if err != nil {
		return "", fmt.Errorf("подключение к RPC: %w", err)
	}
	defer client.Close()

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

	return str, nil
}
