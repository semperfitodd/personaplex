import "./App.css";

function App() {
  return (
    <div className="app">
      <header className="app-header">
        <h1>PersonaPlex</h1>
      </header>
      <iframe
        className="moshi-frame"
        src="/moshi/"
        allow="microphone"
        title="PersonaPlex Voice Chat"
      />
    </div>
  );
}

export default App;
