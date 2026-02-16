export const SAMPLE_RATE = 24000;
export const FRAME_SIZE = 480; // 20ms at 24kHz
const FRAME_DURATION_US = (FRAME_SIZE / SAMPLE_RATE) * 1_000_000;

export function checkBrowserSupport(): string | null {
  if (!("AudioContext" in window)) {
    return "Web Audio API is not supported in this browser.";
  }
  if (!("AudioEncoder" in window) || !("AudioDecoder" in window)) {
    return "WebCodecs API is not supported. Please use Chrome or Edge.";
  }
  if (!navigator.mediaDevices?.getUserMedia) {
    return "Microphone access is not available in this browser.";
  }
  return null;
}

/* ── sphn framing helpers ── */

export function encodeSphnFrame(packet: Uint8Array): Uint8Array {
  const len = packet.length;
  const frame = new Uint8Array(3 + len);
  frame[0] = len & 0xff;
  frame[1] = (len >> 8) & 0xff;
  frame[2] = (len >> 16) & 0xff;
  frame.set(packet, 3);
  return frame;
}

export function decodeSphnFrames(data: Uint8Array): Uint8Array[] {
  const packets: Uint8Array[] = [];
  let offset = 0;
  while (offset + 3 <= data.length) {
    const len =
      data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16);
    offset += 3;
    if (offset + len > data.length) break;
    packets.push(data.slice(offset, offset + len));
    offset += len;
  }
  return packets;
}

/* ── Microphone capture via AudioWorklet ── */

const WORKLET_CODE = `
class PCMProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this._buf = new Float32Array(${FRAME_SIZE});
    this._off = 0;
  }
  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (!ch) return true;
    let i = 0;
    while (i < ch.length) {
      const need = ${FRAME_SIZE} - this._off;
      const n = Math.min(need, ch.length - i);
      this._buf.set(ch.subarray(i, i + n), this._off);
      this._off += n;
      i += n;
      if (this._off === ${FRAME_SIZE}) {
        this.port.postMessage(this._buf.slice());
        this._off = 0;
      }
    }
    return true;
  }
}
registerProcessor('pcm-processor', PCMProcessor);
`;

export class MicCapture {
  private ctx: AudioContext | null = null;
  private stream: MediaStream | null = null;
  private source: MediaStreamAudioSourceNode | null = null;
  private worklet: AudioWorkletNode | null = null;

  onPcmFrame: ((pcm: Float32Array) => void) | null = null;

  async start(): Promise<void> {
    this.ctx = new AudioContext({ sampleRate: SAMPLE_RATE });
    if (this.ctx.state === "suspended") await this.ctx.resume();

    const blob = new Blob([WORKLET_CODE], { type: "application/javascript" });
    const url = URL.createObjectURL(blob);
    await this.ctx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);

    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: SAMPLE_RATE,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
      },
    });

    this.source = this.ctx.createMediaStreamSource(this.stream);
    this.worklet = new AudioWorkletNode(this.ctx, "pcm-processor");
    this.worklet.port.onmessage = (e: MessageEvent<Float32Array>) => {
      this.onPcmFrame?.(e.data);
    };
    this.source.connect(this.worklet);
  }

  stop(): void {
    this.worklet?.disconnect();
    this.source?.disconnect();
    this.stream?.getTracks().forEach((t) => t.stop());
    void this.ctx?.close();
    this.ctx = null;
    this.stream = null;
    this.source = null;
    this.worklet = null;
  }
}

/* ── Opus encoder (WebCodecs) ── */

export class OpusEncoder {
  private encoder: AudioEncoder | null = null;
  private ts = 0;

  onPacket: ((packet: Uint8Array) => void) | null = null;

  async init(): Promise<void> {
    const cfg: AudioEncoderConfig = {
      codec: "opus",
      sampleRate: SAMPLE_RATE,
      numberOfChannels: 1,
      bitrate: 64_000,
    };
    const support = await AudioEncoder.isConfigSupported(cfg);
    if (!support.supported) {
      throw new Error("Opus encoding is not supported in this browser.");
    }

    this.encoder = new AudioEncoder({
      output: (chunk: EncodedAudioChunk) => {
        const buf = new Uint8Array(chunk.byteLength);
        chunk.copyTo(buf);
        this.onPacket?.(buf);
      },
      error: (e: DOMException) => console.error("OpusEncoder:", e),
    });
    this.encoder.configure(cfg);
  }

  encode(pcm: Float32Array): void {
    if (!this.encoder || this.encoder.state !== "configured") return;
    const ad = new AudioData({
      format: "f32-planar",
      sampleRate: SAMPLE_RATE,
      numberOfFrames: pcm.length,
      numberOfChannels: 1,
      timestamp: this.ts,
      data: pcm as Float32Array<ArrayBuffer>,
    });
    this.encoder.encode(ad);
    ad.close();
    this.ts += (pcm.length / SAMPLE_RATE) * 1_000_000;
  }

  close(): void {
    if (this.encoder && this.encoder.state !== "closed") {
      this.encoder.close();
    }
    this.encoder = null;
  }
}

/* ── Opus decoder (WebCodecs) ── */

export class OpusDecoder {
  private decoder: AudioDecoder | null = null;
  private ts = 0;

  onPcm: ((pcm: Float32Array) => void) | null = null;

  async init(): Promise<void> {
    const cfg: AudioDecoderConfig = {
      codec: "opus",
      sampleRate: SAMPLE_RATE,
      numberOfChannels: 1,
    };
    const support = await AudioDecoder.isConfigSupported(cfg);
    if (!support.supported) {
      throw new Error("Opus decoding is not supported in this browser.");
    }

    this.decoder = new AudioDecoder({
      output: (audioData: AudioData) => {
        const pcm = new Float32Array(audioData.numberOfFrames);
        audioData.copyTo(pcm, { planeIndex: 0 });
        this.onPcm?.(pcm);
        audioData.close();
      },
      error: (e: DOMException) => console.error("OpusDecoder:", e),
    });
    this.decoder.configure(cfg);
  }

  decode(packet: Uint8Array): void {
    if (!this.decoder || this.decoder.state !== "configured") return;
    const chunk = new EncodedAudioChunk({
      type: "key",
      timestamp: this.ts,
      data: packet,
    });
    this.decoder.decode(chunk);
    this.ts += FRAME_DURATION_US;
  }

  close(): void {
    if (this.decoder && this.decoder.state !== "closed") {
      this.decoder.close();
    }
    this.decoder = null;
  }
}

/* ── Realtime audio playback ── */

export class AudioPlayer {
  private ctx: AudioContext;
  private gain: GainNode;
  private nextTime = 0;

  constructor() {
    this.ctx = new AudioContext({ sampleRate: SAMPLE_RATE });
    this.gain = this.ctx.createGain();
    this.gain.connect(this.ctx.destination);
  }

  async resume(): Promise<void> {
    if (this.ctx.state === "suspended") await this.ctx.resume();
  }

  play(pcm: Float32Array): void {
    const buf = this.ctx.createBuffer(1, pcm.length, SAMPLE_RATE);
    buf.copyToChannel(pcm as Float32Array<ArrayBuffer>, 0);
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    src.connect(this.gain);

    const now = this.ctx.currentTime;
    if (this.nextTime < now) this.nextTime = now + 0.02;
    src.start(this.nextTime);
    this.nextTime += buf.duration;
  }

  stop(): void {
    this.nextTime = 0;
    void this.ctx.close();
  }
}
