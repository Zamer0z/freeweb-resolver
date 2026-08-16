#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="$HOME/sdk"
GO_BIN="$SDK_DIR/go/bin/go"
IPFS_BIN="$SDK_DIR/kubo/kubo/ipfs"
export IPFS_PATH="$HOME/.ipfs-freeweb"
LOG_DIR="$HOME/Library/Logs"
AGENTS_DIR="$HOME/Library/LaunchAgents"
ARCH="$(uname -m)"

echo "==> Проверяю Go"
if [ ! -x "$GO_BIN" ]; then
	echo "    ставлю Go..."
	mkdir -p "$SDK_DIR"
	curl -sL -o /tmp/freeweb-go.tar.gz "https://go.dev/dl/go1.23.4.darwin-${ARCH}.tar.gz"
	tar -xzf /tmp/freeweb-go.tar.gz -C "$SDK_DIR"
	rm /tmp/freeweb-go.tar.gz
fi
echo "    $("$GO_BIN" version)"

echo "==> Проверяю kubo (IPFS-нода)"
if [ ! -x "$IPFS_BIN" ]; then
	echo "    ставлю kubo..."
	mkdir -p "$SDK_DIR/kubo"
	LATEST=$(curl -s https://dist.ipfs.tech/kubo/versions | tail -1)
	curl -sL -o /tmp/freeweb-kubo.tar.gz "https://dist.ipfs.tech/kubo/${LATEST}/kubo_${LATEST}_darwin-${ARCH}.tar.gz"
	tar -xzf /tmp/freeweb-kubo.tar.gz -C "$SDK_DIR/kubo"
	rm /tmp/freeweb-kubo.tar.gz
fi
echo "    $("$IPFS_BIN" version)"

echo "==> Собираю resolver"
cd "$REPO_DIR"
"$GO_BIN" build -o resolver .

echo "==> Инициализирую IPFS-репозиторий (если ещё нет)"
if [ ! -f "$IPFS_PATH/config" ]; then
	"$IPFS_BIN" init
fi

echo "==> Настраиваю автозапуск через launchd (без root — это обычные пользовательские агенты)"
mkdir -p "$AGENTS_DIR" "$LOG_DIR"

cat >"$AGENTS_DIR/com.freeweb-resolver.ipfs.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.freeweb-resolver.ipfs</string>
	<key>ProgramArguments</key>
	<array><string>${IPFS_BIN}</string><string>daemon</string></array>
	<key>EnvironmentVariables</key>
	<dict><key>IPFS_PATH</key><string>${IPFS_PATH}</string></dict>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>StandardOutPath</key><string>${LOG_DIR}/freeweb-resolver-ipfs.log</string>
	<key>StandardErrorPath</key><string>${LOG_DIR}/freeweb-resolver-ipfs.log</string>
</dict>
</plist>
PLIST

cat >"$AGENTS_DIR/com.freeweb-resolver.resolver.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.freeweb-resolver.resolver</string>
	<key>ProgramArguments</key>
	<array><string>${REPO_DIR}/resolver</string></array>
	<key>WorkingDirectory</key><string>${REPO_DIR}</string>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>StandardOutPath</key><string>${LOG_DIR}/freeweb-resolver.log</string>
	<key>StandardErrorPath</key><string>${LOG_DIR}/freeweb-resolver.log</string>
</dict>
</plist>
PLIST

launchctl unload "$AGENTS_DIR/com.freeweb-resolver.ipfs.plist" 2>/dev/null || true
launchctl unload "$AGENTS_DIR/com.freeweb-resolver.resolver.plist" 2>/dev/null || true
launchctl load "$AGENTS_DIR/com.freeweb-resolver.ipfs.plist"
launchctl load "$AGENTS_DIR/com.freeweb-resolver.resolver.plist"

echo "    автозапуск настроен: резолвер и IPFS-нода теперь сами стартуют при входе"
echo "    в систему и сами перезапускаются, если упадут (launchd KeepAlive)."

echo "==> Жду, пока resolver создаст локальный CA..."
for i in $(seq 1 20); do
	[ -f "$REPO_DIR/ca/ca.crt" ] && break
	sleep 1
done
if [ ! -f "$REPO_DIR/ca/ca.crt" ]; then
	echo "CA не появился за 20 секунд — проверь $LOG_DIR/freeweb-resolver.log" >&2
	exit 1
fi

echo
echo "==> Осталось два системных шага — потребуется твой пароль один раз"
echo "    (это как у любого установщика, ничего необычного):"
sudo -v

sudo security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$REPO_DIR/ca/ca.crt"
sudo mkdir -p /etc/resolver
sudo sh -c "printf 'nameserver 127.0.0.1\nport 15353\n' > /etc/resolver/eth"
sudo sh -c "printf 'nameserver 127.0.0.1\nport 15353\n' > /etc/resolver/test"

echo
echo "Готово! Открой в браузере: https://vitalik.eth:15443/"
echo "Перезагрузи Mac когда угодно — всё поднимется само."
