/** Shared Cloud Agents API v1 types — keep in sync with CursorPocket Swift models. */

export interface AgentSummary {
  id: string;
  name: string;
  status: string;
  url?: string;
  latestRunId?: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface AgentsListResponse {
  items: AgentSummary[];
  nextCursor?: string;
}

export interface PromptPayload {
  text?: string;
}

export interface AgentRun {
  id: string;
  agentId: string;
  status: string;
  prompt?: PromptPayload;
  result?: string;
  durationMs?: number;
  createdAt?: string;
  updatedAt?: string;
}

export interface RunsListResponse {
  items: AgentRun[];
  nextCursor?: string;
}

export interface AgentDetail {
  id: string;
  name: string;
  status: string;
  url?: string;
  latestRunId?: string;
  repos?: { url: string; startingRef?: string }[];
}

export interface CreateAgentResponse {
  agent: AgentDetail;
  run: AgentRun;
}

export interface CreateRunResponse {
  run: AgentRun;
}

export interface APIKeyInfo {
  apiKeyName?: string;
  userEmail?: string;
  userFirstName?: string;
  userLastName?: string;
}

export interface AppSettings {
  repositoryURL: string;
  startingBranch: string;
  chatOnlyMode: boolean;
}

export const DEFAULT_SETTINGS: AppSettings = {
  repositoryURL: "",
  startingBranch: "main",
  chatOnlyMode: true,
};

export type StreamEvent =
  | { type: "status"; status: string }
  | { type: "assistant"; text: string }
  | { type: "result"; text?: string; status: string }
  | { type: "done" }
  | { type: "error"; message: string };
