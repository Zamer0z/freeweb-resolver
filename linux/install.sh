#!/usr/bin/env bash
# Установка freeweb-resolver на Linux. Полностью отдельный путь от
# macOS-версии в корне репозитория — ничего общего в исполнении, чтобы
# изменения тут никогда не могли задеть рабочую macOS-конфигурацию.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_DIR="$HOME/sdk"
GO_BIN="$SDK_DIR/go/bin/go"
IPFS_BIN="$SDK_DIR/kubo/kubo/ipfs"
export IPFS_PATH="$HOME/.ipfs-freeweb"
LOG_DIR="$HOME/.local/share/freeweb-resolver/logs"
UNITS_DIR="$HOME/.config/systemd/user"

case "$(uname -m)" in
x86_64) ARCH="amd64" ;;
aarch64) ARCH="arm64" ;;
*)
	echo "Неизвестная архитектура: $(uname -m)" >&2
	exit 1
	;;
esac

echo "==> Проверяю Go"
if [ ! -x "$GO_BIN" ]; then
	echo "    ставлю Go..."
	mkdir -p "$SDK_DIR"
	curl -sL -o /tmp/freeweb-go.tar.gz "https://go.dev/dl/go1.23.4.linux-${ARCH}.tar.gz"
	tar -xzf /tmp/freeweb-go.tar.gz -C "$SDK_DIR"
	rm /tmp/freeweb-go.tar.gz
fi
echo "    $("$GO_BIN" version)"

echo "==> Проверяю kubo (IPFS-нода)"
if [ ! -x "$IPFS_BIN" ]; then
	echo "    ставлю kubo..."
	mkdir -p "$SDK_DIR/kubo"
	LATEST=$(curl -s https://dist.ipfs.tech/kubo/versions | tail -1)
	curl -sL -o /tmp/freeweb-kubo.tar.gz "https://dist.ipfs.tech/kubo/${LATEST}/kubo_${LATEST}_linux-${ARCH}.tar.gz"
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

mkdir -p "$LOG_DIR" "$UNITS_DIR"

echo "==> Настраиваю автозапуск через systemd --user"

cat >"$UNITS_DIR/freeweb-resolver-ipfs.service" <<UNIT
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

cat >"$UNITS_DIR/freeweb-resolver.service" <<UNIT
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

echo "    systemd --user: резолвер и IPFS-нода сами стартуют и сами перезапускаются при падении"

# Без lingering сервисы --user останавливаются при выходе из сессии —
# для настоящего "переживёт перезапуск" это нужно разрешить отдельно.
if command -v loginctl >/dev/null 2>&1; then
	sudo loginctl enable-linger "$USER" 2>/dev/null ||
		echo "    (не удалось включить lingering — сервисы поднимутся при входе, но не раньше)"
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

echo
echo "==> Осталось два системных шага — потребуется твой пароль:"

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

echo
echo "Готово! Открой в браузере: https://vitalik.eth:15443/"
echo "Перезагружай систему когда угодно — systemd поднимет сервисы сам."
echo
echo "⚠️  Этот путь собран и проверен логически (кросс-компиляция + go vet),"
echo "    но не обкатан на настоящем Linux-железе. Если что-то не так — issue в репозитории."
