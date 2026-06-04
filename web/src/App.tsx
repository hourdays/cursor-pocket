import { useCallback, useEffect, useRef, useState } from "react";
import type { AgentSummary, AppSettings } from "@shared/api/types";
import {
  agentWebURL,
  cancelRun,
  createAgent,
  createRun,
  getRun,
  listAgents,
  streamRun,
  validateAPIKey,
} from "@shared/api/cloudAgentsClient";
import {
  clearAPIKey,
  loadAPIKey,
  loadSettings,
  saveAPIKey,
  saveSettings,
} from "./storage";

type View = "connect" | "idea" | "chat" | "settings";

interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  text: string;
  streaming?: boolean;
}

export function App() {
  const [apiKey, setApiKey] = useState<string | null>(() => loadAPIKey());
  const [accountLabel, setAccountLabel] = useState<string | null>(null);
  const [settings, setSettings] = useState<AppSettings>(() => loadSettings());
  const [view, setView] = useState<View>(apiKey ? "idea" : "connect");
  const [agents, setAgents] = useState<AgentSummary[]>([]);
  const [activeAgentId, setActiveAgentId] = useState<string | null>(null);
  const [activeAgentName, setActiveAgentName] = useState("New chat");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [ideaDraft, setIdeaDraft] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [currentRunId, setCurrentRunId] = useState<string | null>(null);
  const [runStatus, setRunStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [keyDraft, setKeyDraft] = useState("");
  const abortRef = useRef<AbortController | null>(null);

  const refreshAgents = useCallback(async () => {
    if (!apiKey) {
      return;
    }
    try {
      const items = await listAgents(apiKey);
      setAgents(items);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, [apiKey]);

  const refreshAccount = useCallback(async () => {
    if (!apiKey) {
      return;
    }
    try {
      const info = await validateAPIKey(apiKey);
      setAccountLabel(info.userEmail ?? info.apiKeyName ?? "Connected");
    } catch {
      setAccountLabel(null);
    }
  }, [apiKey]);

  useEffect(() => {
    if (apiKey) {
      void refreshAccount();
      void refreshAgents();
    }
  }, [apiKey, refreshAccount, refreshAgents]);

  const connect = async () => {
    setError(null);
    const trimmed = keyDraft.trim();
    if (!trimmed) {
      return;
    }
    try {
      await validateAPIKey(trimmed);
      saveAPIKey(trimmed);
      setApiKey(trimmed);
      setView("idea");
      setKeyDraft("");
      await refreshAccount();
      await refreshAgents();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const signOut = () => {
    abortRef.current?.abort();
    clearAPIKey();
    setApiKey(null);
    setAccountLabel(null);
    setAgents([]);
    setMessages([]);
    setActiveAgentId(null);
    setView("connect");
  };

  const openAgent = (agent: AgentSummary) => {
    setActiveAgentId(agent.id);
    setActiveAgentName(agent.name);
    setMessages([]);
    setView("chat");
    setError(null);
  };

  const consumeStream = async (agentId: string, runId: string) => {
    if (!apiKey) {
      return;
    }

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    let assistantId: string | null = null;

    const appendAssistant = (delta: string) => {
      setMessages((prev) => {
        if (assistantId) {
          return prev.map((m) =>
            m.id === assistantId ? { ...m, text: m.text + delta } : m
          );
        }
        const id = crypto.randomUUID();
        assistantId = id;
        return [
          ...prev,
          { id, role: "assistant", text: delta, streaming: true },
        ];
      });
    };

    const finalize = (text?: string) => {
      setMessages((prev) =>
        prev.map((m) => {
          if (m.id !== assistantId) {
            return m;
          }
          return {
            ...m,
            text: text && text.length > 0 ? text : m.text,
            streaming: false,
          };
        })
      );
    };

    try {
      await streamRun(
        apiKey,
        agentId,
        runId,
        (event) => {
          switch (event.type) {
            case "status":
              setRunStatus(event.status);
              break;
            case "assistant":
              appendAssistant(event.text);
              break;
            case "result":
              setRunStatus(event.status);
              finalize(event.text);
              break;
            case "done":
              finalize();
              setIsSending(false);
              break;
            case "error":
              setError(event.message);
              setIsSending(false);
              break;
          }
        },
        controller.signal
      );

      const run = await getRun(apiKey, agentId, runId);
      setRunStatus(run.status);
      if (run.result) {
        finalize(run.result);
      }
      setIsSending(false);
      setCurrentRunId(null);
    } catch (e) {
      if (controller.signal.aborted) {
        return;
      }
      const message = e instanceof Error ? e.message : String(e);
      if (message.includes("expired") && apiKey) {
        try {
          const run = await getRun(apiKey, agentId, runId);
          finalize(run.result);
          setRunStatus(run.status);
        } catch {
          setError(message);
        }
      } else {
        setError(message);
      }
      setIsSending(false);
    }
  };

  const sendPrompt = async (text: string, options: { newAgent: boolean }) => {
    if (!apiKey || !text.trim() || isSending) {
      return;
    }

    const prompt = text.trim();
    setMessages((prev) => [
      ...prev,
      { id: crypto.randomUUID(), role: "user", text: prompt },
    ]);
    setIsSending(true);
    setError(null);
    setRunStatus("CREATING");
    setView("chat");

    try {
      if (options.newAgent) {
        const response = await createAgent(apiKey, prompt, settings);
        setActiveAgentId(response.agent.id);
        setActiveAgentName(response.agent.name);
        setCurrentRunId(response.run.id);
        await refreshAgents();
        await consumeStream(response.agent.id, response.run.id);
      } else if (activeAgentId) {
        const run = await createRun(apiKey, activeAgentId, prompt);
        setCurrentRunId(run.id);
        await consumeStream(activeAgentId, run.id);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setIsSending(false);
    }
  };

  const startFromIdea = () => {
    void sendPrompt(ideaDraft, { newAgent: true });
    setIdeaDraft("");
  };

  const updateSettings = (patch: Partial<AppSettings>) => {
    const next = { ...settings, ...patch };
    setSettings(next);
    saveSettings(next);
  };

  if (!apiKey || view === "connect") {
    return (
      <div className="connect-card">
        <h1>Cursor Pocket</h1>
        <p className="muted">
          Connect your Cursor account with an API key. Usage is billed to your
          existing Cursor subscription — no separate Pocket fee.
        </p>
        <p className="muted">
          Need a plan?{" "}
          <a href="https://cursor.com" target="_blank" rel="noreferrer">
            cursor.com
          </a>
          {" · "}
          <a href="https://cursor.com/dashboard" target="_blank" rel="noreferrer">
            Get API key
          </a>
        </p>
        <input
          type="password"
          placeholder="Cursor API key"
          value={keyDraft}
          onChange={(e) => setKeyDraft(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && void connect()}
        />
        {error && <p className="error-banner">{error}</p>}
        <button type="button" className="btn btn-primary" onClick={() => void connect()}>
          Connect account
        </button>
        <p className="muted" style={{ fontSize: "0.8rem" }}>
          Unofficial client — not affiliated with Cursor / Anysphere. Web stores
          your key in this browser only.
        </p>
      </div>
    );
  }

  if (view === "settings") {
    return (
      <div className="main">
        <header className="topbar">
          <span className="brand">Settings</span>
          <button type="button" className="btn btn-ghost" onClick={() => setView("idea")}>
            Back
          </button>
        </header>
        <div className="settings-panel">
          {accountLabel && (
            <p className="muted">
              Signed in as <strong>{accountLabel}</strong>
            </p>
          )}
          <label>
            <span>
              <input
                type="checkbox"
                checked={settings.chatOnlyMode}
                onChange={(e) => updateSettings({ chatOnlyMode: e.target.checked })}
              />{" "}
              Chat-only (no GitHub repo) — best for first ideas & Q&A
            </span>
          </label>
          {!settings.chatOnlyMode && (
            <>
              <label>
                GitHub repo URL
                <input
                  value={settings.repositoryURL}
                  onChange={(e) =>
                    updateSettings({ repositoryURL: e.target.value })
                  }
                  placeholder="https://github.com/org/repo"
                />
              </label>
              <label>
                Branch
                <input
                  value={settings.startingBranch}
                  onChange={(e) =>
                    updateSettings({ startingBranch: e.target.value })
                  }
                  placeholder="main"
                />
              </label>
            </>
          )}
          <button type="button" className="btn" onClick={() => void signOut()}>
            Sign out
          </button>
        </div>
      </div>
    );
  }

  if (view === "idea") {
    return (
      <div className="app-shell">
        <Sidebar
          agents={agents}
          activeId={activeAgentId}
          onSelect={openAgent}
          onNew={() => {
            setActiveAgentId(null);
            setMessages([]);
            setView("idea");
          }}
          onSettings={() => setView("settings")}
          accountLabel={accountLabel}
        />
        <div className="main">
          <header className="topbar">
            <span className="brand">Cursor Pocket</span>
            <button type="button" className="btn btn-ghost" onClick={() => setView("settings")}>
              Settings
            </button>
          </header>
          <section className="idea-hero">
            <h2>What do you want to build?</h2>
            <p className="muted">
              Describe your idea — a cloud agent will run on Cursor&apos;s servers.
              {settings.chatOnlyMode
                ? " Chat-only mode: no repo required."
                : " Coding tasks use your configured repo."}
            </p>
            <textarea
              value={ideaDraft}
              onChange={(e) => setIdeaDraft(e.target.value)}
              placeholder="e.g. Add a dark mode toggle to my app and open a PR…"
            />
            {error && <p className="error-banner">{error}</p>}
            <button
              type="button"
              className="btn btn-primary"
              disabled={!ideaDraft.trim() || isSending}
              onClick={startFromIdea}
            >
              {isSending ? "Starting agent…" : "Start agent"}
            </button>
          </section>
        </div>
      </div>
    );
  }

  return (
    <div className="app-shell">
      <Sidebar
        agents={agents}
        activeId={activeAgentId}
        onSelect={openAgent}
        onNew={() => {
          setActiveAgentId(null);
          setMessages([]);
          setView("idea");
        }}
        onSettings={() => setView("settings")}
        accountLabel={accountLabel}
      />
      <div className="main">
        <header className="topbar">
          <div>
            <div className="brand">{activeAgentName}</div>
            {activeAgentId && (
              <a
                className="muted"
                href={agentWebURL(activeAgentId)}
                target="_blank"
                rel="noreferrer"
              >
                Open in Cursor →
              </a>
            )}
          </div>
          <button type="button" className="btn btn-ghost" onClick={() => setView("idea")}>
            New idea
          </button>
        </header>

        <div className="chat">
          {messages.length === 0 && (
            <p className="muted">Send a message to continue this agent.</p>
          )}
          {messages.map((m) => (
            <div key={m.id} className={`bubble ${m.role}`}>
              {m.text || (m.streaming ? "…" : "")}
            </div>
          ))}
        </div>

        {runStatus && isSending && (
          <div className="status-pill">Status: {runStatus}</div>
        )}
        {error && <div className="error-banner">{error}</div>}

        <div className="composer-wrap">
          <form
            className="composer"
            onSubmit={(e) => {
              e.preventDefault();
              if (isSending && activeAgentId && apiKey && currentRunId) {
                void (async () => {
                  abortRef.current?.abort();
                  await cancelRun(apiKey, activeAgentId, currentRunId);
                  setIsSending(false);
                  setCurrentRunId(null);
                  setRunStatus("CANCELLED");
                })();
                return;
              }
              void sendPrompt(draft, { newAgent: !activeAgentId });
              setDraft("");
            }}
          >
            <textarea
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder="Message"
              rows={1}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  e.currentTarget.form?.requestSubmit();
                }
              }}
            />
            <button
              type="submit"
              className="btn btn-primary"
              disabled={!isSending && !draft.trim()}
            >
              {isSending ? "Stop" : "Send"}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

function Sidebar({
  agents,
  activeId,
  onSelect,
  onNew,
  onSettings,
  accountLabel,
}: {
  agents: AgentSummary[];
  activeId: string | null;
  onSelect: (a: AgentSummary) => void;
  onNew: () => void;
  onSettings: () => void;
  accountLabel: string | null;
}) {
  return (
    <aside className="sidebar">
      <div className="brand">Pocket</div>
      {accountLabel && <div className="muted">{accountLabel}</div>}
      <button type="button" className="btn btn-primary" onClick={onNew}>
        + New idea
      </button>
      <div className="agent-list">
        {agents.map((agent) => (
          <button
            key={agent.id}
            type="button"
            className={`agent-item ${agent.id === activeId ? "active" : ""}`}
            onClick={() => onSelect(agent)}
          >
            <strong>{agent.name}</strong>
            <span className="muted">{agent.status}</span>
          </button>
        ))}
      </div>
      <button type="button" className="btn btn-ghost" onClick={onSettings}>
        Settings
      </button>
    </aside>
  );
}
