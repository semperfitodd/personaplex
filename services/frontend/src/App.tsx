import { useState } from "react";
import "./App.css";

function App() {
  const [voicePrompt, setVoicePrompt] = useState("NATF2.pt");
  const [textPrompt, setTextPrompt] = useState("You are a friendly assistant.");
  const [chatUrl, setChatUrl] = useState<string | null>(null);

  const handleStart = () => {
    const params = new URLSearchParams();
    if (voicePrompt) params.set("voice_prompt", voicePrompt);
    if (textPrompt) params.set("text_prompt", textPrompt);
    setChatUrl(`/moshi/?${params.toString()}`);
  };

  const handleStop = () => {
    setChatUrl(null);
  };

  return (
    <div className="app">
      <header className="app-header">
        <h1>PersonaPlex</h1>
        <p className="subtitle">AI Voice Conversations</p>
      </header>

      {!chatUrl ? (
        <main className="config-view">
          <section className="config-panel">
            <div className="config-group">
              <label htmlFor="voice-prompt">Voice Prompt</label>
              <input
                id="voice-prompt"
                type="text"
                placeholder="e.g. NATF2.pt"
                value={voicePrompt}
                onChange={(e) => setVoicePrompt(e.target.value)}
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
              />
            </div>
          </section>

          <div className="action-area">
            <button className="start-btn" onClick={handleStart}>
              Start Conversation
            </button>
          </div>
        </main>
      ) : (
        <main className="chat-view">
          <iframe
            className="moshi-frame"
            src={chatUrl}
            allow="microphone"
            title="PersonaPlex Voice Chat"
          />
          <button className="back-btn" onClick={handleStop}>
            Back to Config
          </button>
        </main>
      )}
    </div>
  );
}

export default App;
