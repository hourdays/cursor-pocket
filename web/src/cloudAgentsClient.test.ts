import { describe, expect, it, vi, afterEach } from "vitest";
import type { AgentRun } from "@shared/api/types";
import {
  loadAgentRunDetails,
  runsToChatMessages,
} from "@shared/api/cloudAgentsClient";

describe("cloudAgentsClient history helpers", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("hydrates list-runs metadata with detailed run results", async () => {
    const runFromList: AgentRun = {
      id: "run-1",
      agentId: "bc-1",
      status: "FINISHED",
      createdAt: "2026-06-06T10:00:00.000Z",
      updatedAt: "2026-06-06T10:01:00.000Z",
    };
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      text: async () =>
        JSON.stringify({
          ...runFromList,
          result: "Final assistant reply",
        }),
    } as Response);
    vi.stubGlobal("fetch", fetchMock);

    await expect(loadAgentRunDetails("key", "bc-1", [runFromList])).resolves.toEqual([
      {
        ...runFromList,
        result: "Final assistant reply",
      },
    ]);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://api.cursor.com/v1/agents/bc-1/runs/run-1",
      expect.objectContaining({
        method: "GET",
        headers: expect.objectContaining({
          Authorization: "Bearer key",
          Accept: "application/json",
        }),
      })
    );
  });

  it("reconstructs chronological chat messages from cached prompts and run results", () => {
    const newer: AgentRun = {
      id: "run-2",
      agentId: "bc-1",
      status: "FINISHED",
      result: "Second reply",
      createdAt: "2026-06-06T10:02:00.000Z",
    };
    const older: AgentRun = {
      id: "run-1",
      agentId: "bc-1",
      status: "FINISHED",
      result: "First reply",
      createdAt: "2026-06-06T10:00:00.000Z",
    };

    expect(
      runsToChatMessages([newer, older], {
        "run-1": "First prompt",
        "run-2": "Second prompt",
      })
    ).toEqual([
      { id: "user-run-1", role: "user", text: "First prompt" },
      { id: "assistant-run-1", role: "assistant", text: "First reply" },
      { id: "user-run-2", role: "user", text: "Second prompt" },
      { id: "assistant-run-2", role: "assistant", text: "Second reply" },
    ]);
  });
});
