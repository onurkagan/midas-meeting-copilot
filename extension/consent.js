// The consent page: shown on the first click, and as the extension's options page.
const tabId = Number(new URLSearchParams(location.search).get("tab")) || null;
const status = document.getElementById("status");

async function show() {
  const { consent } = await chrome.storage.local.get("consent");
  document.getElementById("ask").hidden = Boolean(consent);
  document.getElementById("given").hidden = !consent;
  status.textContent = consent ? `You allowed Midas for Chrome on ${new Date(consent.at).toLocaleString()}.` : "";
}

document.getElementById("allow").addEventListener("click", async () => {
  await chrome.storage.local.set({ consent: { version: 1, at: Date.now() } });
  await show();
  const started = tabId ? await chrome.runtime.sendMessage({ target: "background", type: "consented", tabId }) : false;
  status.textContent = started
    ? "Allowed. Midas now hears the tab you clicked the button on; you can close this page."
    : "Allowed. Now click the Midas button on your call's tab.";
});

document.getElementById("cancel").addEventListener("click", () => window.close());

document.getElementById("withdraw").addEventListener("click", async () => {
  await chrome.storage.local.remove("consent");
  await chrome.runtime.sendMessage({ target: "background", type: "withdrawn" });
  await show();
  status.textContent = "Withdrawn. Midas no longer hears any tab until you allow it again.";
});

show();
