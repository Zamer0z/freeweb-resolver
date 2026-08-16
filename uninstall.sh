#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "==> Останавливаю и убираю автозапуск"
launchctl unload "$AGENTS_DIR/com.freeweb-resolver.ipfs.plist" 2>/dev/null || true
launchctl unload "$AGENTS_DIR/com.freeweb-resolver.resolver.plist" 2>/dev/null || true
rm -f "$AGENTS_DIR/com.freeweb-resolver.ipfs.plist" "$AGENTS_DIR/com.freeweb-resolver.resolver.plist"

echo "==> Убираю CA из доверенных и split-DNS (нужен пароль)"
sudo security remove-trusted-cert -d "$REPO_DIR/ca/ca.crt" 2>/dev/null || true
sudo rm -f /etc/resolver/eth /etc/resolver/test

echo "==> Удаляю сам CA (приватный ключ)"
rm -rf "$REPO_DIR/ca"

echo
echo "Готово. IPFS-репозиторий (~/.ipfs-freeweb) и сам код не тронуты —"
echo "удали их вручную, если они больше не нужны."
