import type { AppSettings } from "@shared/api/types";
import { DEFAULT_SETTINGS } from "@shared/api/types";

const API_KEY = "cursor-pocket.apiKey";
const SETTINGS = "cursor-pocket.settings";
const RUN_PROMPTS = "cursor-pocket.runPrompts";

type StoredRunPrompts = Record<string, Record<string, string>>;

export function loadAPIKey(): string | null {
  return localStorage.getItem(API_KEY);
}

export function saveAPIKey(key: string): void {
  localStorage.setItem(API_KEY, key);
}

export function clearAPIKey(): void {
  localStorage.removeItem(API_KEY);
}

function readRunPrompts(): StoredRunPrompts {
  try {
    const raw = localStorage.getItem(RUN_PROMPTS);
    if (!raw) {
      return {};
    }
    const parsed = JSON.parse(raw);
    return typeof parsed === "object" && parsed !== null
      ? (parsed as StoredRunPrompts)
      : {};
  } catch {
    return {};
  }
}

export function loadRunPrompts(agentId: string): Record<string, string> {
  return { ...(readRunPrompts()[agentId] ?? {}) };
}

export function saveRunPrompt(
  agentId: string,
  runId: string,
  prompt: string
): void {
  const trimmed = prompt.trim();
  if (!trimmed) {
    return;
  }
  const stored = readRunPrompts();
  stored[agentId] = { ...(stored[agentId] ?? {}), [runId]: trimmed };
  localStorage.setItem(RUN_PROMPTS, JSON.stringify(stored));
}

export function clearRunPrompts(): void {
  localStorage.removeItem(RUN_PROMPTS);
}

export function loadSettings(): AppSettings {
  try {
    const raw = localStorage.getItem(SETTINGS);
    if (!raw) {
      return { ...DEFAULT_SETTINGS };
    }
    return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) } as AppSettings;
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export function saveSettings(settings: AppSettings): void {
  localStorage.setItem(SETTINGS, JSON.stringify(settings));
}
