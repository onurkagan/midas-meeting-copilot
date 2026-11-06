// Mixes the tab down to mono and sends it on in 100 ms batches of 16-bit PCM.
class PcmBatcher extends AudioWorkletProcessor {
  constructor() {
    super();
    this.batch = new Int16Array(1600); // 100 ms at 16 kHz
    this.filled = 0;
  }

  process(inputs) {
    const channels = inputs[0];
    if (!channels || channels.length === 0) return true;
    const frames = channels[0].length;
    for (let i = 0; i < frames; i++) {
      let sum = 0;
      for (const channel of channels) sum += channel[i];
      const sample = Math.max(-1, Math.min(1, sum / channels.length));
      this.batch[this.filled++] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
      if (this.filled === this.batch.length) {
        this.port.postMessage(this.batch.buffer, [this.batch.buffer]);
        this.batch = new Int16Array(1600);
        this.filled = 0;
      }
    }
    return true;
  }
}

registerProcessor("pcm", PcmBatcher);
