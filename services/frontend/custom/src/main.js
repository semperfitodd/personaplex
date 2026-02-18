import Recorder from 'opus-recorder';
import { decodeMessage, encodeAudio } from './protocol.js';
import './style.css';

const BASE = import.meta.env.BASE_URL;

const DEFAULTS = {
  textTemperature: 0.7,
  textTopk: 25,
  audioTemperature: 0.65,
  audioTopk: 80,
  padMult: 0,
  repetitionPenaltyContext: 64,
  repetitionPenalty: 1.05,
};

function createWarmupBosPage() {
  const opusHead = new Uint8Array([
    0x4f, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64,
    0x01, 0x01, 0x38, 0x01, 0x80, 0xbb, 0x00, 0x00,
    0x00, 0x00, 0x00,
  ]);
  const pageHeader = new Uint8Array([
    0x4f, 0x67, 0x67, 0x53, 0x00, 0x02,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x01, 0x13,
  ]);
  const bos = new Uint8Array(pageHeader.length + opusHead.length);
  bos.set(pageHeader, 0);
  bos.set(opusHead, pageHeader.length);
  return bos;
}

let audioContext = null;
let workletNode = null;
let recorder = null;
let ws = null;
let decoderWorker = null;
let micDuration = 0;
let connected = false;
let micStream = null;
let micAnalyser = null;
let animFrame = null;
let smoothLevel = 0;

const statusDot = document.getElementById('status-dot');
const statusText = document.getElementById('status-text');
const connectBtn = document.getElementById('connect-btn');
const connectBtnLabel = connectBtn.querySelector('span');
const transcript = document.getElementById('transcript');
const orb = document.getElementById('orb');
const orbGlow = document.getElementById('orb-glow');
const orbHint = document.getElementById('orb-hint');
const rings = document.querySelectorAll('.ring');
const configToggle = document.getElementById('config-toggle');
const sheetBackdrop = document.getElementById('sheet-backdrop');
const configSheet = document.getElementById('config-sheet');
const sheetClose = document.getElementById('sheet-close');
const voiceSelect = document.getElementById('voice-select');
const promptInput = document.getElementById('prompt-input');
const presetBtns = document.querySelectorAll('.preset-btn');

function setStatus(status) {
  statusDot.className = status;
  const labels = { disconnected: 'Disconnected', connecting: 'Connecting...', connected: 'Connected' };
  statusText.textContent = labels[status] || status;

  const isConnected = status === 'connected';
  orb.classList.toggle('active', isConnected);
  orbGlow.classList.toggle('active', isConnected);
  rings.forEach((r) => r.classList.toggle('active', isConnected));

  if (isConnected) {
    orbHint.textContent = 'Listening...';
    orbHint.classList.add('hidden');
  } else if (status === 'connecting') {
    orbHint.textContent = 'Connecting...';
    orbHint.classList.remove('hidden');
  } else {
    orbHint.textContent = 'Tap connect to start talking';
    orbHint.classList.remove('hidden');
  }

  if (isConnected) {
    connectBtnLabel.textContent = 'Disconnect';
    connectBtn.classList.add('danger');
  } else {
    connectBtnLabel.textContent = status === 'connecting' ? 'Connecting...' : 'Connect';
    connectBtn.classList.remove('danger');
    connectBtn.disabled = status === 'connecting';
  }
}

function appendText(text) {
  const existing = transcript.lastElementChild;
  if (existing && existing.classList.contains('model-text')) {
    existing.textContent += text;
  } else {
    const el = document.createElement('p');
    el.className = 'model-text';
    el.textContent = text;
    transcript.appendChild(el);
  }
  transcript.scrollTop = transcript.scrollHeight;
}

async function initAudio() {
  if (audioContext) return;
  audioContext = new AudioContext();
  await audioContext.audioWorklet.addModule(BASE + 'audio-processor.js');
  workletNode = new AudioWorkletNode(audioContext, 'moshi-processor');
  workletNode.connect(audioContext.destination);
}

function initDecoder() {
  if (decoderWorker) decoderWorker.terminate();
  decoderWorker = new Worker(BASE + 'assets/decoderWorker.min.js');

  decoderWorker.postMessage({
    command: 'init',
    bufferLength: Math.round(960 * audioContext.sampleRate / 24000),
    decoderSampleRate: 24000,
    outputBufferSampleRate: audioContext.sampleRate,
    resampleQuality: 0,
  });

  setTimeout(() => {
    decoderWorker.postMessage({ command: 'decode', pages: createWarmupBosPage() });
  }, 100);

  decoderWorker.onmessage = (e) => {
    if (!e.data) return;
    workletNode.port.postMessage({ frame: e.data[0], type: 'audio', micDuration });
  };
}

function buildWSUrl() {
  const proto = window.location.protocol === 'https:' ? 'wss' : 'ws';
  const url = new URL(`${proto}://${window.location.host}${BASE}api/chat`);

  url.searchParams.set('text_temperature', DEFAULTS.textTemperature);
  url.searchParams.set('text_topk', DEFAULTS.textTopk);
  url.searchParams.set('audio_temperature', DEFAULTS.audioTemperature);
  url.searchParams.set('audio_topk', DEFAULTS.audioTopk);
  url.searchParams.set('pad_mult', DEFAULTS.padMult);
  url.searchParams.set('repetition_penalty_context', DEFAULTS.repetitionPenaltyContext);
  url.searchParams.set('repetition_penalty', DEFAULTS.repetitionPenalty);
  url.searchParams.set('text_seed', Math.round(Math.random() * 1_000_000));
  url.searchParams.set('audio_seed', Math.round(Math.random() * 1_000_000));
  url.searchParams.set('text_prompt', promptInput.value);
  url.searchParams.set('voice_prompt', voiceSelect.value);

  return url.toString();
}

function startOrbAnimation() {
  if (!micAnalyser) return;
  const dataArray = new Float32Array(micAnalyser.fftSize);

  function animate() {
    micAnalyser.getFloatTimeDomainData(dataArray);
    let sum = 0;
    for (let i = 0; i < dataArray.length; i++) sum += dataArray[i] * dataArray[i];
    const level = Math.min(Math.sqrt(sum / dataArray.length) / 0.12, 1);

    smoothLevel += (level - smoothLevel) * 0.25;
    orb.style.transform = `scale(${1 + smoothLevel * 0.3})`;
    orbGlow.style.opacity = 0.3 + smoothLevel * 0.7;
    orbGlow.style.transform = `scale(${1 + smoothLevel * 0.15})`;

    animFrame = requestAnimationFrame(animate);
  }

  animFrame = requestAnimationFrame(animate);
}

function stopOrbAnimation() {
  if (animFrame) {
    cancelAnimationFrame(animFrame);
    animFrame = null;
  }
  smoothLevel = 0;
  orb.style.transform = '';
  orbGlow.style.opacity = '';
  orbGlow.style.transform = '';
}

async function startMic() {
  micStream = await navigator.mediaDevices.getUserMedia({
    audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 },
  });

  const sourceNode = audioContext.createMediaStreamSource(micStream);
  micAnalyser = audioContext.createAnalyser();
  micAnalyser.fftSize = 256;
  sourceNode.connect(micAnalyser);
  startOrbAnimation();

  recorder = new Recorder({
    sourceNode,
    encoderPath: BASE + 'assets/encoderWorker.min.js',
    bufferLength: Math.round(960 * audioContext.sampleRate / 24000),
    encoderFrameSize: 20,
    encoderSampleRate: 24000,
    maxFramesPerPage: 2,
    numberOfChannels: 1,
    recordingGain: 1,
    resampleQuality: 3,
    encoderComplexity: 0,
    encoderApplication: 2049,
    streamPages: true,
  });

  recorder.ondataavailable = (data) => {
    micDuration = recorder.encodedSamplePosition / 48000;
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(encodeAudio(data instanceof Uint8Array ? data : new Uint8Array(data)));
    }
  };

  recorder.start().catch((err) => console.error('Mic start failed:', err));
}

function stopMic() {
  stopOrbAnimation();
  if (recorder) {
    try { recorder.stop(); } catch (_) { /* already stopped */ }
    recorder = null;
  }
  if (micStream) {
    micStream.getTracks().forEach((t) => t.stop());
    micStream = null;
  }
  micAnalyser = null;
  micDuration = 0;
}

function cleanup() {
  connected = false;
  setStatus('disconnected');
  stopMic();
  if (decoderWorker) {
    decoderWorker.terminate();
    decoderWorker = null;
  }
}

async function connect() {
  await initAudio();
  await audioContext.resume();
  transcript.innerHTML = '';
  setStatus('connecting');
  initDecoder();
  workletNode.port.postMessage({ type: 'reset' });

  ws = new WebSocket(buildWSUrl());
  ws.binaryType = 'arraybuffer';

  ws.addEventListener('message', (e) => {
    const msg = decodeMessage(new Uint8Array(e.data));

    switch (msg.type) {
      case 'handshake':
        connected = true;
        setStatus('connected');
        startMic();
        break;
      case 'audio':
        if (decoderWorker) {
          decoderWorker.postMessage({ command: 'decode', pages: msg.data }, [msg.data.buffer]);
        }
        break;
      case 'text':
        appendText(msg.data);
        break;
      case 'error':
        console.error('Server error:', msg.data);
        appendText(`[Error] ${msg.data}`);
        break;
    }
  });

  ws.addEventListener('close', () => {
    ws = null;
    cleanup();
  });

  ws.addEventListener('error', (err) => console.error('WebSocket error:', err));
}

function disconnect() {
  if (ws) {
    ws.close();
    ws = null;
  }
  cleanup();
}

connectBtn.addEventListener('click', () => {
  if (connected || (ws && ws.readyState === WebSocket.CONNECTING)) {
    disconnect();
  } else {
    connect();
  }
});

function openSheet() {
  configSheet.classList.add('open');
  sheetBackdrop.classList.add('open');
}

function closeSheet() {
  configSheet.classList.remove('open');
  sheetBackdrop.classList.remove('open');
}

configToggle.addEventListener('click', openSheet);
sheetClose.addEventListener('click', closeSheet);
sheetBackdrop.addEventListener('click', closeSheet);

presetBtns.forEach((btn) => {
  btn.addEventListener('click', () => { promptInput.value = btn.dataset.prompt; });
});

setStatus('disconnected');
