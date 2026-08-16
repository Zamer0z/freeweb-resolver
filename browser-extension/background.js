const STATUS_URL = "http://127.0.0.1:15380/_freeweb/status";
const ALARM_NAME = "freeweb-status-check";

async function checkStatus() {
  try {
    const res = await fetch(STATUS_URL, { cache: "no-store" });
    const data = await res.json();

    if (data.resolver && data.ipfs) {
      chrome.action.setBadgeText({ text: "✓" }); // ✓
      chrome.action.setBadgeBackgroundColor({ color: "#2ecc71" });
      chrome.action.setTitle({ title: "freeweb-resolver: работает (резолвер + IPFS)" });
    } else if (data.resolver) {
      chrome.action.setBadgeText({ text: "!" });
      chrome.action.setBadgeBackgroundColor({ color: "#f39c12" });
      chrome.action.setTitle({ title: "freeweb-resolver: резолвер жив, IPFS-нода недоступна" });
    } else {
      throw new Error("resolver reports not ok");
    }
  } catch (e) {
    chrome.action.setBadgeText({ text: "✕" }); // ✗
    chrome.action.setBadgeBackgroundColor({ color: "#e74c3c" });
    chrome.action.setTitle({ title: "freeweb-resolver: не отвечает" });
  }
}

chrome.runtime.onInstalled.addListener(() => {
  checkStatus();
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: 0.5 });
});

chrome.runtime.onStartup.addListener(checkStatus);

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_NAME) checkStatus();
});

// ---------------------------------------------------------------------------
// Автоматический редирект: .eth-имена по умолчанию идут на порт 443, где
// наш шлюз не слушает (он на 15443, чтобы не требовать root). Ловим именно
// эту неудачную попытку и молча перенаправляем на рабочий адрес — так можно
// печатать vitalik.eth (или https://vitalik.eth) как обычный сайт, без
// ручного дописывания порта.
// ---------------------------------------------------------------------------

const GATEWAY_PORT = "15443";
const RETRYABLE_ERRORS = new Set([
  "net::ERR_NAME_NOT_RESOLVED",
  "net::ERR_CONNECTION_REFUSED",
  "net::ERR_SSL_PROTOCOL_ERROR",
]);

function isEthHost(urlString) {
  try {
    return new URL(urlString).hostname.endsWith(".eth");
  } catch {
    return false;
  }
}

function toGatewayURL(urlString) {
  const u = new URL(urlString);
  // Редиректим только с "дефолтного" порта — иначе можно зациклиться,
  // если и сам шлюз по какой-то причине недоступен.
  if (u.port !== "" && u.port !== "443") return null;
  u.protocol = "https:";
  u.port = GATEWAY_PORT;
  return u.toString();
}

chrome.webNavigation.onErrorOccurred.addListener((details) => {
  if (details.frameId !== 0) return; // только основной фрейм страницы
  if (!isEthHost(details.url)) return;
  if (!RETRYABLE_ERRORS.has(details.error)) return;

  const target = toGatewayURL(details.url);
  if (!target || target === details.url) return;

  chrome.tabs.update(details.tabId, { url: target });
});
