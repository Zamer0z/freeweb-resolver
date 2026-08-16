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
