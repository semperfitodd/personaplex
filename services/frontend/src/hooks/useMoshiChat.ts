import { useState, useRef, useCallback, useEffect } from "react";
import {
  checkBrowserSupport,
  encodeSphnFrame,
  decodeSphnFrames,
  MicCapture,
  OpusEncoder,
  OpusDecoder,
  AudioPlayer,
} from "../lib/audio";

export type ConnectionStatus =
  | "disconnected"
  | "connecting"
  | "waiting"
  | "ready"
  | "error";

export interface MoshiChatOptions {
  wsUrl: string;
  voicePrompt: string;
  textPrompt: string;
}

const MSG_HANDSHAKE = 0x00;
const MSG_AUDIO = 0x01;
const MSG_TEXT = 0x02;

export function useMoshiChat() {
  const [status, setStatus] = useState<ConnectionStatus>("disconnected");
  const [transcript, setTranscript] = useState("");
  const [error, setError] = useState<string | null>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const micRef = useRef<MicCapture | null>(null);
  const encRef = useRef<OpusEncoder | null>(null);
  const decRef = useRef<OpusDecoder | null>(null);
  const playerRef = useRef<AudioPlayer | null>(null);

  const cleanup = useCallback(() => {
    const ws = wsRef.current;
    if (ws) {
      ws.onclose = null;
      ws.onerror = null;
      ws.onmessage = null;
      ws.close();
      wsRef.current = null;
    }
    micRef.current?.stop();
    micRef.current = null;
    encRef.current?.close();
    encRef.current = null;
    decRef.current?.close();
    decRef.current = null;
    playerRef.current?.stop();
    playerRef.current = null;
  }, []);

  const connect = useCallback(
    async (opts: MoshiChatOptions) => {
      cleanup();
      setError(null);
      setTranscript("");
      setStatus("connecting");

      try {
        const unsupported = checkBrowserSupport();
        if (unsupported) throw new Error(unsupported);

        // Audio playback
        const player = new AudioPlayer();
        await player.resume();
        playerRef.current = player;

        // Opus decoder  →  player
        const dec = new OpusDecoder();
        dec.onPcm = (pcm) => player.play(pcm);
        await dec.init();
        decRef.current = dec;

        // Opus encoder
        const enc = new OpusEncoder();
        await enc.init();
        encRef.current = enc;

        // WebSocket
        const params = new URLSearchParams();
        if (opts.voicePrompt) params.set("voice_prompt", opts.voicePrompt);
        if (opts.textPrompt) params.set("text_prompt", opts.textPrompt);
        const url = `${opts.wsUrl}?${params.toString()}`;

        const ws = new WebSocket(url);
        ws.binaryType = "arraybuffer";
        wsRef.current = ws;

        // Encoder  →  WebSocket
        enc.onPacket = (packet) => {
          if (ws.readyState === WebSocket.OPEN) {
            const frame = encodeSphnFrame(packet);
            const msg = new Uint8Array(1 + frame.length);
            msg[0] = MSG_AUDIO;
            msg.set(frame, 1);
            ws.send(msg.buffer);
          }
        };

        ws.onopen = () => setStatus("waiting");

        ws.onmessage = async (ev: MessageEvent) => {
          const data = new Uint8Array(ev.data as ArrayBuffer);
          if (data.length === 0) return;

          const type = data[0];
          const payload = data.subarray(1);

          switch (type) {
            case MSG_HANDSHAKE: {
              setStatus("ready");
              const mic = new MicCapture();
              mic.onPcmFrame = (pcm) => enc.encode(pcm);
              await mic.start();
              micRef.current = mic;
              break;
            }
            case MSG_AUDIO: {
              const packets = decodeSphnFrames(payload);
              for (const p of packets) dec.decode(p);
              break;
            }
            case MSG_TEXT: {
              const text = new TextDecoder().decode(payload);
              setTranscript((prev) => prev + text);
              break;
            }
          }
        };

        ws.onerror = () => {
          setError("WebSocket connection failed.");
          setStatus("error");
          cleanup();
        };

        ws.onclose = () => {
          setStatus((prev) => (prev === "error" ? prev : "disconnected"));
          cleanup();
        };
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
        setStatus("error");
        cleanup();
      }
    },
    [cleanup],
  );

  const disconnect = useCallback(() => {
    cleanup();
    setStatus("disconnected");
  }, [cleanup]);

  useEffect(() => cleanup, [cleanup]);

  return { status, transcript, error, connect, disconnect };
}
