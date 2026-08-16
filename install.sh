#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="$HOME/sdk"
GO_BIN="$SDK_DIR/go/bin/go"
IPFS_BIN="$SDK_DIR/kubo/kubo/ipfs"
export IPFS_PATH="$HOME/.ipfs-freeweb"
LOG_DIR="$HOME/Library/Logs"
OS="$(uname -s)"

if [ "$OS" = "Linux" ]; then
	LOG_DIR="$HOME/.local/share/freeweb-resolver/logs"
fi

echo "==> ОС: $OS ($(uname -m))"

# ---------------------------------------------------------------------------
# Go / kubo — механизм установки одинаковый для macOS и Linux, отличается
# только имя архива.
# ---------------------------------------------------------------------------

goos_name() {
	case "$OS" in
	Darwin) echo "darwin" ;;
	Linux) echo "linux" ;;
	*)
		echo "Неизвестная ОС: $OS. Поддерживаются только macOS и Linux." >&2
		exit 1
		;;
	esac
}

goarch_name() {
	case "$(uname -m)" in
	x86_64) echo "amd64" ;;
	arm64 | aarch64) echo "arm64" ;;
	*)
		echo "Неизвестная архитектура: $(uname -m)" >&2
		exit 1
		;;
	esac
}

GOOS_NAME="$(goos_name)"
GOARCH_NAME="$(goarch_name)"

echo "==> Проверяю Go"
if [ ! -x "$GO_BIN" ]; then
	echo "    ставлю Go..."
	mkdir -p "$SDK_DIR"
	curl -sL -o /tmp/freeweb-go.tar.gz "https://go.dev/dl/go1.23.4.${GOOS_NAME}-${GOARCH_NAME}.tar.gz"
	tar -xzf /tmp/freeweb-go.tar.gz -C "$SDK_DIR"
	rm /tmp/freeweb-go.tar.gz
fi
echo "    $("$GO_BIN" version)"

echo "==> Проверяю kubo (IPFS-нода)"
if [ ! -x "$IPFS_BIN" ]; then
	echo "    ставлю kubo..."
	mkdir -p "$SDK_DIR/kubo"
	LATEST=$(curl -s https://dist.ipfs.tech/kubo/versions | tail -1)
	curl -sL -o /tmp/freeweb-kubo.tar.gz "https://dist.ipfs.tech/kubo/${LATEST}/kubo_${LATEST}_${GOOS_NAME}-${GOARCH_NAME}.tar.gz"
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

mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Автозапуск: launchd на macOS, systemd --user на Linux.
# ---------------------------------------------------------------------------

setup_launchd() {
	local agents_dir="$HOME/Library/LaunchAgents"
	mkdir -p "$agents_dir"

	cat >"$agents_dir/com.freeweb-resolver.ipfs.plist" <<PLIST
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

	cat >"$agents_dir/com.freeweb-resolver.resolver.plist" <<PLIST
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

	launchctl unload "$agents_dir/com.freeweb-resolver.ipfs.plist" 2>/dev/null || true
	launchctl unload "$agents_dir/com.freeweb-resolver.resolver.plist" 2>/dev/null || true
	launchctl load "$agents_dir/com.freeweb-resolver.ipfs.plist"
	launchctl load "$agents_dir/com.freeweb-resolver.resolver.plist"
}

setup_systemd_user() {
	local units_dir="$HOME/.config/systemd/user"
	mkdir -p "$units_dir"

	cat >"$units_dir/freeweb-resolver-ipfs.service" <<UNIT
[Unit]
Description=freeweb-resolver: IPFS node (kubo)

[Service]
ExecStart=${IPFS_BIN} daemon
Environment=IPFS_PATH=${IPFS_PATH}
Restart=on-failure
RestartSec=3
StandardOutput=append:${LOG_DIR}/freeweb-resolver-ipfs.log
StandardError=append:${LOG_DIR}/freeweb-resolver-ipfs.log

[Install]
WantedBy=default.target
UNIT

	cat >"$units_dir/freeweb-resolver.service" <<UNIT
[Unit]
Description=freeweb-resolver: local DNS/HTTPS gateway for .eth
After=freeweb-resolver-ipfs.service

[Service]
ExecStart=${REPO_DIR}/resolver
WorkingDirectory=${REPO_DIR}
Restart=on-failure
RestartSec=3
StandardOutput=append:${LOG_DIR}/freeweb-resolver.log
StandardError=append:${LOG_DIR}/freeweb-resolver.log

[Install]
WantedBy=default.target
UNIT

	systemctl --user daemon-reload
	systemctl --user enable --now freeweb-resolver-ipfs.service freeweb-resolver.service

	# Без этого автозапуск сработает только пока у пользователя есть
	# активная сессия — lingering разрешает сервисам жить и после выхода/ребута.
	if command -v loginctl >/dev/null 2>&1; then
		sudo loginctl enable-linger "$USER" 2>/dev/null ||
			echo "    (не удалось включить lingering — сервисы поднимутся при входе в систему, но не раньше)"
	fi
}

echo "==> Настраиваю автозапуск"
if [ "$OS" = "Darwin" ]; then
	setup_launchd
	echo "    launchd: резолвер и IPFS-нода сами стартуют при входе и сами перезапускаются при падении"
else
	setup_systemd_user
	echo "    systemd --user: резолвер и IPFS-нода сами стартуют и сами перезапускаются при падении"
fi

echo "==> Жду, пока resolver создаст локальный CA..."
for i in $(seq 1 20); do
	[ -f "$REPO_DIR/ca/ca.crt" ] && break
	sleep 1
done
if [ ! -f "$REPO_DIR/ca/ca.crt" ]; then
	echo "CA не появился за 20 секунд — проверь логи в $LOG_DIR" >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# Доверие CA + split-DNS — системные шаги, требуют пароль. Механизм разный
# на macOS и Linux.
# ---------------------------------------------------------------------------

echo
echo "==> Осталось два системных шага — потребуется твой пароль один раз:"
sudo -v

if [ "$OS" = "Darwin" ]; then
	sudo security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$REPO_DIR/ca/ca.crt"

	sudo mkdir -p /etc/resolver
	sudo sh -c "printf 'nameserver 127.0.0.1\nport 15353\n' > /etc/resolver/eth"
	sudo sh -c "printf 'nameserver 127.0.0.1\nport 15353\n' > /etc/resolver/test"
else
	# CA: определяем, какой трастсторой пользоваться, по наличию утилиты,
	# а не по названию дистрибутива — надёжнее.
	if command -v update-ca-certificates >/dev/null 2>&1; then
		sudo cp "$REPO_DIR/ca/ca.crt" /usr/local/share/ca-certificates/freeweb-resolver.crt
		sudo update-ca-certificates
	elif command -v update-ca-trust >/dev/null 2>&1; then
		sudo cp "$REPO_DIR/ca/ca.crt" /etc/pki/ca-trust/source/anchors/freeweb-resolver.crt
		sudo update-ca-trust extract
	else
		echo "    Не нашёл update-ca-certificates/update-ca-trust — добавь" >&2
		echo "    $REPO_DIR/ca/ca.crt в доверенные корневые сертификаты вручную." >&2
	fi

	# Split-DNS: только если есть systemd-resolved. Без него — честно
	# предупреждаем, а не притворяемся, что настроили.
	if command -v resolvectl >/dev/null 2>&1; then
		IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
		if [ -n "${IFACE:-}" ]; then
			sudo resolvectl dns "$IFACE" 127.0.0.1:15353
			sudo resolvectl domain "$IFACE" "~eth" "~test"
		else
			echo "    Не нашёл сетевой интерфейс по умолчанию — настрой split-DNS вручную:" >&2
			echo "    resolvectl dns <интерфейс> 127.0.0.1:15353 && resolvectl domain <интерфейс> '~eth' '~test'" >&2
		fi
	else
		echo "    systemd-resolved (resolvectl) не найден — split-DNS не настроен автоматически." >&2
		echo "    Проверить домены можно вручную: curl --resolve vitalik.eth:15443:127.0.0.1 https://vitalik.eth:15443/" >&2
	fi
fi

echo
echo "Готово! Открой в браузере: https://vitalik.eth:15443/"
if [ "$OS" = "Darwin" ]; then
	echo "Перезагружай Mac когда угодно — всё поднимется само."
else
	echo "Перезагружай систему когда угодно — systemd поднимет сервисы сам."
fi
echo
echo "⚠️  Linux-ветка этого скрипта не обкатана на реальном железе — собрана и"
echo "    проверена логически (бинарник кросс-компилируется и линтится чисто),"
echo "    но живого прогона на настоящем Linux не было. Если что-то пошло не"
echo "    так — заведи issue в репозитории."
