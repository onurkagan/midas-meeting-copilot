// Midas for Chrome: click the toolbar button on a call tab and that tab's audio goes to
// Midas on this Mac, through the native messaging host (dev.midas.tab). Click again to stop.
// Nothing leaves the Mac, and Midas hears this tab only, not the browser's other tabs.

const HOST = "dev.midas.tab";
let port = null; // the native host, while a tab is being sent
let capturing = null; // the tab being sent: { id, title }

chrome.action.onClicked.addListener(async (tab) => {
  if (capturing?.id === tab.id) {
    stop("stopped from the toolbar");
    return;
  }
  // Nothing is captured before the user has read what the extension does and allowed it.
  const { consent } = await chrome.storage.local.get("consent");
  if (!consent) {
    chrome.tabs.create({ url: `consent.html?tab=${tab.id}` });
    return;
  }
  await start(tab);
});

async function start(tab) {
  if (capturing) stop("another tab chosen");
  try {
    // Asked here, in the click: Chrome allows tab capture only on the user's gesture.
    const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
    port = chrome.runtime.connectNative(HOST);
    port.onMessage.addListener(onHostMessage);
    port.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError?.message;
      port = null;
      if (capturing) stop(error ? `Midas disconnected: ${error}` : "Midas disconnected");
    });
    capturing = { id: tab.id, title: tab.title || "Chrome tab" };
    port.postMessage({ type: "start", title: capturing.title, url: tab.url || "" });
    await ensureOffscreen();
    await chrome.runtime.sendMessage({ target: "offscreen", type: "start", streamId });
    badge("ON", "#1B62A8", `Midas hears this tab. Click to stop.`);
    return true;
  } catch (error) {
    stop(`couldn't start: ${error.message || error}`);
    return false;
  }
}

function onHostMessage(message) {
  if (message.type === "error") {
    badge("!", "#C2410C", message.message);
    stopCapture();
  }
}

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  // Only this extension's own pages and scripts; web pages can't message it at all.
  if (sender.id !== chrome.runtime.id || message.target !== "background") return;
  if (message.type === "consented") {
    // Allowed on the consent page: start on the tab whose button was clicked, if Chrome
    // still lets us (it does until that tab navigates); otherwise the user clicks again.
    chrome.tabs.get(message.tabId).then(start, () => false).then(reply);
    return true;
  }
  if (message.type === "withdrawn") {
    if (capturing) stop("consent withdrawn");
    reply(true);
    return;
  }
  if (message.type === "audio" && port) {
    port.postMessage({ type: "audio", pcm: message.pcm });
  } else if (message.type === "ended") {
    stop("the tab stopped playing");
  } else if (message.type === "meet-mute" && port && sender.origin === "https://meet.google.com" && sender.tab?.id === capturing?.id) {
    // Meet's own microphone button: muted in Meet means muted in Midas too.
    port.postMessage({ type: "mute", muted: message.muted });
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  if (tabId === capturing?.id) stop("the tab was closed");
});

function stop(reason) {
  if (port) {
    port.postMessage({ type: "stop", reason });
    port.disconnect();
    port = null;
  }
  stopCapture();
  console.info(`Midas: ${reason}`);
}

function stopCapture() {
  capturing = null;
  chrome.runtime.sendMessage({ target: "offscreen", type: "stop" }).catch(() => {});
  chrome.action.setBadgeText({ text: "" });
  chrome.action.setTitle({ title: "Send this tab's audio to Midas" });
}

function badge(text, color, title) {
  chrome.action.setBadgeText({ text });
  chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setTitle({ title });
}

async function ensureOffscreen() {
  if (await chrome.offscreen.hasDocument()) return;
  await chrome.offscreen.createDocument({
    url: "offscreen.html",
    reasons: ["USER_MEDIA"],
    justification: "Captures the call tab's audio, keeps it playing for you and sends it to Midas.",
  });
}
