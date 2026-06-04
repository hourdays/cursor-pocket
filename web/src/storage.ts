import type { AppSettings } from "@shared/api/types";
import { DEFAULT_SETTINGS } from "@shared/api/types";

const API_KEY = "cursor-pocket.apiKey";
const SETTINGS = "cursor-pocket.settings";

export function loadAPIKey(): string | null {
  return localStorage.getItem(API_KEY);
}

export function saveAPIKey(key: string): void {
  localStorage.setItem(API_KEY, key);
}

export function clearAPIKey(): void {
  localStorage.removeItem(API_KEY);
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
