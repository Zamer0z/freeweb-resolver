#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v go >/dev/null 2>&1; then
	echo "Go не найден. Поставь Go (https://go.dev/dl/) и повтори." >&2
	exit 1
fi

echo "==> Собираю resolver"
go build -o resolver .

echo "==> Проверяю IPFS-ноду (kubo)"
if ! command -v ipfs >/dev/null 2>&1; then
	echo "    ipfs не найден в PATH. Поставь kubo: https://dist.ipfs.tech/kubo"
	echo "    и один раз выполни 'ipfs init', затем 'ipfs daemon &' перед запуском resolver."
else
	echo "    ipfs найден: $(ipfs version)"
fi

echo
echo "Сборка готова. Дальше — шаги, которые требуют твоего пароля и не"
echo "автоматизируются из скрипта (интерактивная авторизация в Связке ключей):"
echo
echo "  1) Запусти резолвер (тестовые порты, ничего в системе не трогает):"
echo "       ./resolver &"
echo
echo "  2) Добавь локальный CA в доверенные:"
echo "       security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db ca/ca.crt"
echo
echo "  3) Проверь без изменения системного DNS:"
echo "       curl --resolve vitalik.eth:15443:127.0.0.1 https://vitalik.eth:15443/"
echo
echo "  4) (опционально) Чтобы .eth резолвился сам, без --resolve, и это НЕ"
echo "     конфликтовало с VPN — используй split-DNS, а не общий DNS системы:"
echo "       sudo mkdir -p /etc/resolver"
echo "       sudo sh -c 'printf \"nameserver 127.0.0.1\\nport 15353\\n\" > /etc/resolver/eth'"
echo "       sudo sh -c 'printf \"nameserver 127.0.0.1\\nport 15353\\n\" > /etc/resolver/test'"
echo
echo "Подробности и как всё это откатить — в README.md."
