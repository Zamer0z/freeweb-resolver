#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

echo "==> Останавливаю и убираю автозапуск"
if [ "$OS" = "Darwin" ]; then
	agents_dir="$HOME/Library/LaunchAgents"
	launchctl unload "$agents_dir/com.freeweb-resolver.ipfs.plist" 2>/dev/null || true
	launchctl unload "$agents_dir/com.freeweb-resolver.resolver.plist" 2>/dev/null || true
	rm -f "$agents_dir/com.freeweb-resolver.ipfs.plist" "$agents_dir/com.freeweb-resolver.resolver.plist"
else
	systemctl --user disable --now freeweb-resolver.service freeweb-resolver-ipfs.service 2>/dev/null || true
	rm -f "$HOME/.config/systemd/user/freeweb-resolver.service" "$HOME/.config/systemd/user/freeweb-resolver-ipfs.service"
	systemctl --user daemon-reload 2>/dev/null || true
fi

echo "==> Убираю CA из доверенных и split-DNS (нужен пароль)"
if [ "$OS" = "Darwin" ]; then
	sudo security remove-trusted-cert -d "$REPO_DIR/ca/ca.crt" 2>/dev/null || true
	sudo rm -f /etc/resolver/eth /etc/resolver/test
else
	sudo rm -f /usr/local/share/ca-certificates/freeweb-resolver.crt /etc/pki/ca-trust/source/anchors/freeweb-resolver.crt
	command -v update-ca-certificates >/dev/null 2>&1 && sudo update-ca-certificates 2>/dev/null || true
	command -v update-ca-trust >/dev/null 2>&1 && sudo update-ca-trust extract 2>/dev/null || true

	if command -v resolvectl >/dev/null 2>&1; then
		IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
		[ -n "${IFACE:-}" ] && sudo resolvectl revert "$IFACE" 2>/dev/null || true
	fi
fi

echo "==> Удаляю сам CA (приватный ключ)"
rm -rf "$REPO_DIR/ca"

echo
echo "Готово. IPFS-репозиторий (~/.ipfs-freeweb) и сам код не тронуты —"
echo "удали их вручную, если они больше не нужны."
