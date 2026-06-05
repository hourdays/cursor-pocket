import type {
  AgentDetail,
  AgentRun,
  AgentSummary,
  AgentsListResponse,
  APIKeyInfo,
  AppSettings,
  CreateAgentResponse,
  CreateRunResponse,
  RunsListResponse,
  StreamEvent,
} from "./types";

const BASE_URL = "https://api.cursor.com/v1";

export class CloudAgentsError extends Error {
  constructor(
    message: string,
    readonly code?: "missing_key" | "agent_busy" | "stream_expired" | "http",
    readonly status?: number
  ) {
    super(message);
    this.name = "CloudAgentsError";
  }
}

async function request<T>(
  path: string,
  apiKey: string,
  method: string,
  body?: unknown
): Promise<T> {
  if (!apiKey.trim()) {
    throw new CloudAgentsError("Add your Cursor API key.", "missing_key");
  }

  const response = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  const text = await response.text();

  if (response.status === 409 && text.includes("agent_busy")) {
    throw new CloudAgentsError(
      "This agent already has a run in progress.",
      "agent_busy",
      409
    );
  }

  if (!response.ok) {
    throw new CloudAgentsError(
      `API error ${response.status}: ${text || response.statusText}`,
      "http",
      response.status
    );
  }

  if (!text) {
    return {} as T;
  }

  return JSON.parse(text) as T;
}

export async function validateAPIKey(apiKey: string): Promise<APIKeyInfo> {
  return request<APIKeyInfo>("/me", apiKey, "GET");
}

export async function listAgents(
  apiKey: string,
  limit = 50
): Promise<AgentSummary[]> {
  const response = await request<AgentsListResponse>(
    `/agents?limit=${limit}`,
    apiKey,
    "GET"
  );
  return response.items ?? [];
}

export async function createAgent(
  apiKey: string,
  prompt: string,
  settings: AppSettings,
  name?: string
): Promise<CreateAgentResponse> {
  const body: Record<string, unknown> = {
    prompt: { text: prompt },
    env: { type: "cloud" },
  };

  if (name?.trim()) {
    body.name = name.trim();
  }

  const repoURL = settings.repositoryURL.trim();
  const branch = settings.startingBranch.trim();

  if (!settings.chatOnlyMode && repoURL) {
    const repo: Record<string, string> = { url: repoURL };
    if (branch) {
      repo.startingRef = branch;
    }
    body.repos = [repo];
    delete body.env;
  }

  return request<CreateAgentResponse>("/agents", apiKey, "POST", body);
}

export async function createRun(
  apiKey: string,
  agentId: string,
  prompt: string
): Promise<AgentRun> {
  const response = await request<CreateRunResponse>(
    `/agents/${agentId}/runs`,
    apiKey,
    "POST",
    { prompt: { text: prompt } }
  );
  return response.run;
}

export async function getRun(
  apiKey: string,
  agentId: string,
  runId: string
): Promise<AgentRun> {
  return request<AgentRun>(`/agents/${agentId}/runs/${runId}`, apiKey, "GET");
}

export async function listAgentRuns(
  apiKey: string,
  agentId: string,
  limit = 50
): Promise<AgentRun[]> {
  const response = await request<RunsListResponse>(
    `/agents/${agentId}/runs?limit=${limit}`,
    apiKey,
    "GET"
  );
  return response.items ?? [];
}

const ACTIVE_RUN_STATUSES = new Set([
  "CREATING",
  "PENDING",
  "RUNNING",
  "QUEUED",
]);

export function isActiveRunStatus(status: string): boolean {
  return ACTIVE_RUN_STATUSES.has(status.toUpperCase());
}

/** Chronological user/assistant pairs from completed or in-progress runs. */
export function runsToChatMessages(
  runs: AgentRun[]
): { id: string; role: "user" | "assistant"; text: string }[] {
  const sorted = [...runs].sort((a, b) =>
    (a.createdAt ?? "").localeCompare(b.createdAt ?? "")
  );
  const messages: { id: string; role: "user" | "assistant"; text: string }[] =
    [];

  for (const run of sorted) {
    const userText = run.prompt?.text?.trim();
    if (userText) {
      messages.push({ id: `user-${run.id}`, role: "user", text: userText });
    }
    const assistantText = run.result?.trim();
    if (assistantText) {
      messages.push({
        id: `assistant-${run.id}`,
        role: "assistant",
        text: assistantText,
      });
    }
  }

  return messages;
}

export async function cancelRun(
  apiKey: string,
  agentId: string,
  runId: string
): Promise<void> {
  await request(`/agents/${agentId}/runs/${runId}/cancel`, apiKey, "POST");
}

function parseSSE(event: string, dataLines: string[]): StreamEvent | null {
  const payload = dataLines.join("\n");
  if (!payload) {
    return null;
  }

  try {
    const json = JSON.parse(payload) as Record<string, unknown>;
    switch (event) {
      case "status":
        return { type: "status", status: String(json.status ?? "") };
      case "assistant":
        return { type: "assistant", text: String(json.text ?? "") };
      case "result":
        return {
          type: "result",
          text: json.text != null ? String(json.text) : undefined,
          status: String(json.status ?? "FINISHED"),
        };
      case "done":
        return { type: "done" };
      case "error":
        return {
          type: "error",
          message: String(json.message ?? payload),
        };
      default:
        return null;
    }
  } catch {
    if (event === "done") {
      return { type: "done" };
    }
    return null;
  }
}

/** Consumes an agent run SSE stream; calls `onEvent` for each parsed event. */
export async function streamRun(
  apiKey: string,
  agentId: string,
  runId: string,
  onEvent: (event: StreamEvent) => void,
  signal?: AbortSignal
): Promise<void> {
  const response = await fetch(
    `${BASE_URL}/agents/${agentId}/runs/${runId}/stream`,
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "text/event-stream",
      },
      signal,
    }
  );

  if (response.status === 410) {
    throw new CloudAgentsError(
      "Stream expired. Loading final reply…",
      "stream_expired",
      410
    );
  }

  if (!response.ok) {
    throw new CloudAgentsError(
      `Stream failed (${response.status})`,
      "http",
      response.status
    );
  }

  const reader = response.body?.getReader();
  if (!reader) {
    throw new CloudAgentsError("No response body for stream.");
  }

  const decoder = new TextDecoder();
  let buffer = "";
  let currentEvent = "";
  let dataLines: string[] = [];

  const flush = () => {
    if (!currentEvent && dataLines.length === 0) {
      return;
    }
    const parsed = parseSSE(currentEvent, dataLines);
    if (parsed) {
      onEvent(parsed);
    }
    currentEvent = "";
    dataLines = [];
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      if (line === "") {
        flush();
        continue;
      }
      if (line.startsWith("event:")) {
        currentEvent = line.slice(6).trim();
      } else if (line.startsWith("data:")) {
        dataLines.push(line.slice(5).trim());
      }
    }
  }

  flush();
}

export function agentWebURL(agentId: string): string {
  return `https://cursor.com/agents/${agentId}`;
}

export async function getAgent(
  apiKey: string,
  agentId: string
): Promise<AgentDetail> {
  return request<AgentDetail>(`/agents/${agentId}`, apiKey, "GET");
}
