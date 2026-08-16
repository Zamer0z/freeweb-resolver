#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Останавливаю и убираю автозапуск"
systemctl --user disable --now freeweb-resolver.service freeweb-resolver-ipfs.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/freeweb-resolver.service" "$HOME/.config/systemd/user/freeweb-resolver-ipfs.service"
systemctl --user daemon-reload 2>/dev/null || true

echo "==> Убираю CA из доверенных (нужен пароль)"
sudo rm -f /usr/local/share/ca-certificates/freeweb-resolver.crt /etc/pki/ca-trust/source/anchors/freeweb-resolver.crt
command -v update-ca-certificates >/dev/null 2>&1 && sudo update-ca-certificates 2>/dev/null || true
command -v update-ca-trust >/dev/null 2>&1 && sudo update-ca-trust extract 2>/dev/null || true

echo "==> Убираю split-DNS"
if command -v resolvectl >/dev/null 2>&1; then
	IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
	[ -n "${IFACE:-}" ] && sudo resolvectl revert "$IFACE" 2>/dev/null || true
fi

echo "==> Удаляю сам CA (приватный ключ)"
rm -rf "$REPO_DIR/ca"

echo
echo "Готово. IPFS-репозиторий (~/.ipfs-freeweb) и сам код не тронуты —"
echo "удали их вручную, если они больше не нужны."
