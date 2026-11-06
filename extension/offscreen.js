// Holds the tab's audio while it is sent to Midas: plays it back (capturing a tab mutes it
// for the user otherwise) and turns it into 16 kHz mono PCM, as Midas's other sources are.

let stream = null;
let playback = null; // the tab at full quality, for the user's ears
let capture = null; // the same audio at 16 kHz, for Midas

chrome.runtime.onMessage.addListener((message, sender) => {
  if (sender.id !== chrome.runtime.id || message.target !== "offscreen") return;
  if (message.type === "start") start(message.streamId).catch((error) => {
    console.error("Midas: couldn't capture the tab", error);
    chrome.runtime.sendMessage({ target: "background", type: "ended" });
  });
  if (message.type === "stop") stop();
});

async function start(streamId) {
  stop();
  stream = await navigator.mediaDevices.getUserMedia({
    audio: { mandatory: { chromeMediaSource: "tab", chromeMediaSourceId: streamId } },
    video: false,
  });
  stream.getAudioTracks()[0].addEventListener("ended", () => {
    stop();
    chrome.runtime.sendMessage({ target: "background", type: "ended" });
  });
  playback = new AudioContext();
  playback.createMediaStreamSource(stream).connect(playback.destination);
  // Chrome resamples into a 16 kHz context, so the worklet only mixes down and batches.
  capture = new AudioContext({ sampleRate: 16000 });
  await capture.audioWorklet.addModule("pcm-worklet.js");
  const node = new AudioWorkletNode(capture, "pcm", { numberOfOutputs: 0 });
  node.port.onmessage = ({ data }) => {
    chrome.runtime.sendMessage({ target: "background", type: "audio", pcm: base64(new Uint8Array(data)) });
  };
  capture.createMediaStreamSource(stream).connect(node);
}

function stop() {
  stream?.getTracks().forEach((track) => track.stop());
  playback?.close();
  capture?.close();
  stream = playback = capture = null;
}

function base64(bytes) {
  let text = "";
  for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(text);
}
