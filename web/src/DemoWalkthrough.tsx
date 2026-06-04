import { useEffect, useState } from "react";

/** Scripted UI tour for screen recordings (`?demo=1`). No API calls. */
export function DemoWalkthrough() {
  const [scene, setScene] = useState(0);
  const [streamText, setStreamText] = useState("");

  const assistantReply =
    "I'll add a dark mode toggle using your theme tokens, wire it in Settings, and open a PR when the run finishes.";

  useEffect(() => {
    const timers = [
      setTimeout(() => setScene(1), 2800),
      setTimeout(() => setScene(2), 6200),
    ];
    return () => timers.forEach(clearTimeout);
  }, []);

  useEffect(() => {
    if (scene !== 2) {
      setStreamText("");
      return;
    }
    let i = 0;
    const id = setInterval(() => {
      i += 1;
      setStreamText(assistantReply.slice(0, i));
      if (i >= assistantReply.length) {
        clearInterval(id);
      }
    }, 28);
    return () => clearInterval(id);
  }, [scene]);

  if (scene === 0) {
    return (
      <div className="connect-card">
        <h1>Cursor Pocket</h1>
        <p className="muted">
          Connect your Cursor account with an API key. Usage is billed to your
          existing Cursor subscription.
        </p>
        <input type="password" placeholder="Cursor API key" value="••••••••••••" readOnly />
        <button type="button" className="btn btn-primary">
          Connect account
        </button>
        <p className="muted" style={{ fontSize: "0.8rem" }}>
          Demo recording — not a real key
        </p>
      </div>
    );
  }

  if (scene === 1) {
    return (
      <div className="app-shell">
        <aside className="sidebar">
          <div className="brand">Pocket</div>
          <div className="muted">you@company.com</div>
          <button type="button" className="btn btn-primary">
            + New idea
          </button>
        </aside>
        <div className="main">
          <header className="topbar">
            <span className="brand">Cursor Pocket</span>
          </header>
          <section className="idea-hero">
            <h2>What do you want to build?</h2>
            <p className="muted">Chat-only mode: no repo required.</p>
            <textarea
              readOnly
              value="Add a dark mode toggle to my app and open a PR when done."
            />
            <button type="button" className="btn btn-primary">
              Start agent
            </button>
          </section>
        </div>
      </div>
    );
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">Pocket</div>
        <div className="muted">you@company.com</div>
        <button type="button" className="btn btn-primary">
          + New idea
        </button>
        <div className="agent-list">
          <button type="button" className="agent-item active">
            <strong>Dark mode toggle</strong>
            <span className="muted">RUNNING</span>
          </button>
        </div>
      </aside>
      <div className="main">
        <header className="topbar">
          <div>
            <div className="brand">Dark mode toggle</div>
            <span className="muted">Open in Cursor →</span>
          </div>
        </header>
        <div className="chat">
          <div className="bubble user">
            Add a dark mode toggle to my app and open a PR when done.
          </div>
          <div className="bubble assistant">
            {streamText}
            {streamText.length < assistantReply.length ? "…" : ""}
          </div>
        </div>
        {scene === 2 && streamText.length < assistantReply.length && (
          <div className="status-pill">Status: RUNNING</div>
        )}
        <div className="composer-wrap">
          <div className="composer">
            <textarea placeholder="Message" rows={1} readOnly />
            <button type="button" className="btn btn-primary" disabled>
              Send
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
