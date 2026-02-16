import { useState, useRef, useEffect } from "react";
import { useMoshiChat, ConnectionStatus } from "./hooks/useMoshiChat";
import "./App.css";

function getWsUrl(): string {
  const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${proto}//${window.location.host}/api/chat`;
}

const STATUS_LABELS: Record<ConnectionStatus, string> = {
  disconnected: "Disconnected",
  connecting: "Connecting",
  waiting: "Waiting for model",
  ready: "Listening",
  error: "Error",
};

const STATUS_CLASSES: Record<ConnectionStatus, string> = {
  disconnected: "dot-grey",
  connecting: "dot-yellow",
  waiting: "dot-yellow",
  ready: "dot-green",
  error: "dot-red",
};

const MicIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" width="36" height="36">
    <path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.91-3c-.49 0-.9.36-.98.85C16.52 14.2 14.47 16 12 16s-4.52-1.8-4.93-4.15a.998.998 0 0 0-.98-.85c-.61 0-1.09.54-1 1.14.49 3 2.89 5.35 5.91 5.78V21c0 .55.45 1 1 1s1-.45 1-1v-3.08c3.02-.43 5.42-2.78 5.91-5.78.1-.6-.39-1.14-1-1.14z" />
  </svg>
);

const StopIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" width="36" height="36">
    <rect x="6" y="6" width="12" height="12" rx="2" />
  </svg>
);

function App() {
  const { status, transcript, error, connect, disconnect } = useMoshiChat();
  const [voicePrompt, setVoicePrompt] = useState("");
  const [textPrompt, setTextPrompt] = useState("You are a friendly assistant.");
  const transcriptRef = useRef<HTMLDivElement>(null);

  const active =
    status === "connecting" || status === "waiting" || status === "ready";

  const handleToggle = () => {
    if (active) {
      disconnect();
    } else {
      connect({
        wsUrl: getWsUrl(),
        voicePrompt,
        textPrompt,
      });
    }
  };

  useEffect(() => {
    if (transcriptRef.current) {
      transcriptRef.current.scrollTop = transcriptRef.current.scrollHeight;
    }
  }, [transcript]);

  return (
    <div className="app">
      <header className="app-header">
        <h1>PersonaPlex</h1>
        <p className="subtitle">AI Voice Conversations</p>
      </header>

      <main className="app-main">
        <section className="config-panel">
          <div className="config-group">
            <label htmlFor="voice-prompt">Voice Prompt</label>
            <input
              id="voice-prompt"
              type="text"
              placeholder="e.g. NATF2.pt"
              value={voicePrompt}
              onChange={(e) => setVoicePrompt(e.target.value)}
              disabled={active}
            />
          </div>
          <div className="config-group">
            <label htmlFor="text-prompt">Persona</label>
            <textarea
              id="text-prompt"
              rows={3}
              placeholder="Describe the persona..."
              value={textPrompt}
              onChange={(e) => setTextPrompt(e.target.value)}
              disabled={active}
            />
          </div>
        </section>

        <div className="action-area">
          <button
            className={`mic-btn ${active ? "mic-btn--active" : ""}`}
            onClick={handleToggle}
            aria-label={active ? "Stop conversation" : "Start conversation"}
          >
            {active ? <StopIcon /> : <MicIcon />}
          </button>
          <span className="action-label">
            {active ? "Stop" : "Start Conversation"}
          </span>
        </div>

        <div className="status-row">
          <span className={`status-dot ${STATUS_CLASSES[status]}`} />
          <span className="status-text">{STATUS_LABELS[status]}</span>
        </div>

        {error && <div className="error-banner">{error}</div>}

        {transcript && (
          <section className="transcript-panel">
            <h3>Transcript</h3>
            <div className="transcript-content" ref={transcriptRef}>
              {transcript}
            </div>
          </section>
        )}
      </main>
    </div>
  );
}

export default App;
