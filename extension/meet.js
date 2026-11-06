// On Google Meet: tells Midas when you mute or unmute yourself in Meet, so Midas's own
// microphone follows. It reads only the microphone button's state, nothing else on the page.

let last = null;

function micMuted() {
  // Meet marks its microphone and camera buttons with data-is-muted; the microphone's
  // label names it, or its shortcut (⌘ + D), whatever the page's language.
  for (const button of document.querySelectorAll("[data-is-muted]")) {
    const label = button.getAttribute("aria-label") || "";
    if (/microphone|mikrofon|micro|\+\s*d\)/i.test(label)) return button.getAttribute("data-is-muted") === "true";
  }
  return null;
}

function check() {
  const muted = micMuted();
  if (muted === null || muted === last) return;
  last = muted;
  chrome.runtime.sendMessage({ target: "background", type: "meet-mute", muted }).catch(() => {});
}

new MutationObserver(check).observe(document.documentElement, {
  subtree: true,
  attributes: true,
  attributeFilter: ["data-is-muted"],
});
check();
