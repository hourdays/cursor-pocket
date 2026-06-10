#!/usr/bin/env node
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const port = "5188";
const baseURL = `http://127.0.0.1:${port}/`;
const allowedEmail = "allowed@example.com";
const storageKey = "cursor-pocket.apiKey";
const apiKey = "test-api-key";

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitFor(condition, message, ms = 30000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    if (await condition()) {
      return;
    }
    await delay(100);
  }
  throw new Error(message);
}

async function waitForServer(url, ms = 30000) {
  await waitFor(
    async () => {
      try {
        const response = await fetch(url);
        return response.ok;
      } catch {
        return false;
      }
    },
    `Server not up: ${url}`,
    ms
  );
}

async function storedKey(page) {
  return page.evaluate((key) => localStorage.getItem(key), storageKey);
}

async function textVisible(page, text) {
  return page.getByText(text).isVisible().catch(() => false);
}

async function newKeyedContext(browser) {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
  });
  await context.addInitScript(
    ({ key, value }) => {
      localStorage.setItem(key, value);
    },
    { key: storageKey, value: apiKey }
  );
  return context;
}

function jsonResponse(status, body) {
  return {
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  };
}

async function runAccessScenario(browser, name, meResponse, expectedStoredKey) {
  const context = await newKeyedContext(browser);
  const page = await context.newPage();
  let meRequests = 0;

  await page.route("https://api.cursor.com/v1/me", async (route) => {
    meRequests += 1;
    await route.fulfill(meResponse);
  });
  await page.route("https://api.cursor.com/v1/agents?**", async (route) => {
    await route.fulfill(jsonResponse(200, { items: [] }));
  });

  await page.goto(baseURL, { waitUntil: "domcontentloaded" });
  await waitFor(() => meRequests > 0, `${name}: /me was not requested`);
  await waitFor(
    async () => (await storedKey(page)) === expectedStoredKey,
    `${name}: expected stored key ${JSON.stringify(expectedStoredKey)}, got ${JSON.stringify(
      await storedKey(page)
    )}`
  );

  await context.close();
  console.log(`ok - ${name}`);
}

async function runAgentSwitchRace(browser) {
  const context = await newKeyedContext(browser);
  const page = await context.newPage();
  let staleDetailReturned = false;

  await page.route("https://api.cursor.com/v1/**", async (route) => {
    const url = new URL(route.request().url());
    const pathname = url.pathname;

    if (pathname === "/v1/me") {
      await route.fulfill(jsonResponse(200, { userEmail: allowedEmail }));
      return;
    }

    if (pathname === "/v1/agents") {
      await route.fulfill(
        jsonResponse(200, {
          items: [
            { id: "agent-a", name: "Agent A", status: "IDLE" },
            { id: "agent-b", name: "Agent B", status: "IDLE" },
          ],
        })
      );
      return;
    }

    if (pathname === "/v1/agents/agent-a") {
      await delay(500);
      staleDetailReturned = true;
      await route.fulfill(
        jsonResponse(200, { id: "agent-a", name: "Agent A detail", status: "IDLE" })
      );
      return;
    }

    if (pathname === "/v1/agents/agent-a/runs") {
      throw new Error("agent switch race: stale run history should not be requested");
    }

    if (pathname === "/v1/agents/agent-b") {
      await route.fulfill(
        jsonResponse(200, { id: "agent-b", name: "Agent B detail", status: "IDLE" })
      );
      return;
    }

    if (pathname === "/v1/agents/agent-b/runs") {
      await route.fulfill(
        jsonResponse(200, {
          items: [
            {
              id: "run-b",
              agentId: "agent-b",
              status: "FINISHED",
              prompt: { text: "Agent B question" },
              result: "Agent B current answer",
              createdAt: "2026-06-10T11:00:01.000Z",
            },
          ],
        })
      );
      return;
    }

    throw new Error(`Unexpected request in agent switch test: ${route.request().url()}`);
  });

  await page.goto(baseURL, { waitUntil: "domcontentloaded" });
  await page.locator(".agent-item", { hasText: "Agent A" }).click();
  await page.locator(".agent-item", { hasText: "Agent B" }).click();

  await waitFor(
    () => textVisible(page, "Agent B current answer"),
    "agent switch race: current agent history did not render"
  );
  await waitFor(
    () => staleDetailReturned,
    "agent switch race: stale detail request did not complete"
  );
  await delay(100);

  if (await textVisible(page, "Agent A stale answer")) {
    throw new Error("agent switch race: stale agent history overwrote current chat");
  }
  if (!(await textVisible(page, "Agent B detail"))) {
    throw new Error("agent switch race: active chat title was overwritten");
  }

  await context.close();
  console.log("ok - rapid agent switch ignores stale history");
}

async function runResultOnlyStream(browser) {
  const context = await newKeyedContext(browser);
  const page = await context.newPage();

  await page.route("https://api.cursor.com/v1/**", async (route) => {
    const url = new URL(route.request().url());
    const pathname = url.pathname;

    if (pathname === "/v1/me") {
      await route.fulfill(jsonResponse(200, { userEmail: allowedEmail }));
      return;
    }

    if (pathname === "/v1/agents") {
      await route.fulfill(
        jsonResponse(200, {
          items: [{ id: "stream-agent", name: "Result Only Agent", status: "RUNNING" }],
        })
      );
      return;
    }

    if (pathname === "/v1/agents/stream-agent") {
      await route.fulfill(
        jsonResponse(200, {
          id: "stream-agent",
          name: "Result Only Agent",
          status: "RUNNING",
          latestRunId: "run-final",
        })
      );
      return;
    }

    if (pathname === "/v1/agents/stream-agent/runs") {
      await route.fulfill(
        jsonResponse(200, {
          items: [
            {
              id: "run-final",
              agentId: "stream-agent",
              status: "RUNNING",
              prompt: { text: "Question with result-only stream" },
              createdAt: "2026-06-10T11:00:02.000Z",
            },
          ],
        })
      );
      return;
    }

    if (pathname === "/v1/agents/stream-agent/runs/run-final/stream") {
      await route.fulfill({
        status: 200,
        contentType: "text/event-stream",
        body:
          'event: result\ndata: {"text":"Final reply only","status":"FINISHED"}\n\n' +
          "event: done\ndata: {}\n\n",
      });
      return;
    }

    if (pathname === "/v1/agents/stream-agent/runs/run-final") {
      await route.fulfill(
        jsonResponse(200, {
          id: "run-final",
          agentId: "stream-agent",
          status: "FINISHED",
          result: "Final reply only",
        })
      );
      return;
    }

    throw new Error(`Unexpected request in result stream test: ${route.request().url()}`);
  });

  await page.goto(baseURL, { waitUntil: "domcontentloaded" });
  await page.locator(".agent-item", { hasText: "Result Only Agent" }).click();
  await waitFor(
    () => textVisible(page, "Final reply only"),
    "result-only stream: final reply was not rendered"
  );

  await context.close();
  console.log("ok - result-only streams render final reply");
}

const server = spawn(
  "npm",
  ["run", "dev", "--", "--host", "127.0.0.1", "--port", port, "--strictPort"],
  {
    cwd: root,
    env: {
      ...process.env,
      VITE_ALLOWED_EMAIL: allowedEmail,
    },
    detached: true,
    stdio: "pipe",
  }
);

let serverExited = false;
const serverExit = new Promise((resolve) => {
  server.on("exit", (code, signal) => {
    serverExited = true;
    resolve({ code, signal });
  });
});

server.stdout.on("data", (chunk) => process.stdout.write(chunk));
server.stderr.on("data", (chunk) => process.stderr.write(chunk));

async function stopServer() {
  if (!serverExited && server.pid) {
    process.kill(-server.pid, "SIGTERM");
    await Promise.race([
      serverExit,
      new Promise((resolve) => setTimeout(resolve, 5000)),
    ]);
  }
}

try {
  await Promise.race([
    waitForServer(baseURL),
    serverExit.then(({ code, signal }) => {
      throw new Error(
        `Vite exited before startup (code ${code ?? "none"}, signal ${
          signal ?? "none"
        })`
      );
    }),
  ]);

  const { chromium } = await import("playwright");
  const browser = await chromium.launch({ headless: true });

  try {
    await runAccessScenario(
      browser,
      "transient account validation failure preserves stored API key",
      jsonResponse(503, { error: "temporarily unavailable" }),
      apiKey
    );

    await runAccessScenario(
      browser,
      "disallowed account email clears stored API key",
      jsonResponse(200, { userEmail: "someone-else@example.com" }),
      null
    );

    await runAgentSwitchRace(browser);
    await runResultOnlyStream(browser);
  } finally {
    await browser.close();
  }
} finally {
  await stopServer();
}
