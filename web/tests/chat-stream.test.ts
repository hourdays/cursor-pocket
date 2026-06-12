import assert from "node:assert/strict";
import { test } from "node:test";

import { streamRun } from "../../shared/api/cloudAgentsClient";
import type { StreamEvent } from "../../shared/api/types";

function mockStreamResponse(body: string): () => void {
  const originalFetch = globalThis.fetch;

  globalThis.fetch = (async (input) => {
    assert.equal(
      String(input),
      "https://api.cursor.com/v1/agents/agent-1/runs/run-1/stream"
    );

    return new Response(
      new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(body));
          controller.close();
        },
      }),
      { status: 200, headers: { "Content-Type": "text/event-stream" } }
    );
  }) as typeof fetch;

  return () => {
    globalThis.fetch = originalFetch;
  };
}

test("streamRun parses CRLF result-only SSE streams", async () => {
  const restoreFetch = mockStreamResponse(
    'event: result\r\ndata: {"text":"final answer","status":"FINISHED"}\r\n\r\nevent: done\r\ndata: {}\r\n\r\n'
  );
  const events: StreamEvent[] = [];

  try {
    await streamRun("key", "agent-1", "run-1", (event) => {
      events.push(event);
    });
  } finally {
    restoreFetch();
  }

  assert.deepEqual(events, [
    { type: "result", text: "final answer", status: "FINISHED" },
    { type: "done" },
  ]);
});
