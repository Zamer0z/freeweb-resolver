package main

import (
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// seedPin просит локальную IPFS-ноду закрепить (запинить) контент чужих
// .eth-сайтов из --seed — чисто добровольная помощь без всякой оплаты и
// без токена: раздаёшь чужой сайт со своей ноды, чтобы он не пропал, если
// хозяин выключит свой компьютер. Это ровно то же самое взаимовыручное
// устройство, что и раздача в торрентах — никто никому не платит.
func seedPin(names []string) {
	// Таймаут большой намеренно: пин — это не пометка, а полная загрузка
	// содержимого по сети, для чужого не закешированного сайта это может
	// занять реально долго. Работает в фоне, не блокирует ничего для
	// пользователя, так что спешить некуда.
	client := &http.Client{Timeout: 5 * time.Minute}

	for _, name := range names {
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}

		contenthash, err := resolveENS(name)
		if err != nil {
			log.Printf("seed: не удалось резолвить %s: %v", name, err)
			continue
		}

		params := url.Values{}
		params.Set("arg", contenthash)
		params.Set("recursive", "true")
		pinURL := cfg.IPFSAPI + "/api/v0/pin/add?" + params.Encode()

		resp, err := client.Post(pinURL, "", nil)
		if err != nil {
			log.Printf("seed: не удалось запинить %s (%s): %v", name, contenthash, err)
			continue
		}
		resp.Body.Close()

		if resp.StatusCode == http.StatusOK {
			log.Printf("seed: %s (%s) закреплён на нашей ноде — помогаем раздавать бесплатно", name, contenthash)
		} else {
			log.Printf("seed: %s (%s) — IPFS API вернул %d", name, contenthash, resp.StatusCode)
		}
	}
}
