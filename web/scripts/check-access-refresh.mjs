#!/usr/bin/env node
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const baseURL = "http://127.0.0.1:5173/";
const allowedEmail = "allowed@example.com";
const storageKey = "cursor-pocket.apiKey";
const apiKey = "test-api-key";

async function waitFor(condition, message, ms = 30000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    if (await condition()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
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

async function runScenario(browser, name, meResponse, expectedStoredKey) {
  const context = await browser.newContext();
  await context.addInitScript(
    ({ key, value }) => {
      localStorage.setItem(key, value);
    },
    { key: storageKey, value: apiKey }
  );

  const page = await context.newPage();
  let meRequests = 0;

  await page.route("https://api.cursor.com/v1/me", async (route) => {
    meRequests += 1;
    await route.fulfill(meResponse);
  });
  await page.route("https://api.cursor.com/v1/agents?**", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ items: [] }),
    });
  });

  await page.goto(baseURL, { waitUntil: "domcontentloaded" });
  await waitFor(() => meRequests > 0, `${name}: /me was not requested`);

  const storedKey = await page.evaluate((key) => localStorage.getItem(key), storageKey);
  if (storedKey !== expectedStoredKey) {
    throw new Error(
      `${name}: expected stored key ${JSON.stringify(
        expectedStoredKey
      )}, got ${JSON.stringify(storedKey)}`
    );
  }

  await context.close();
  console.log(`ok - ${name}`);
}

const server = spawn("npm", ["run", "dev", "--", "--host", "127.0.0.1"], {
  cwd: root,
  env: {
    ...process.env,
    VITE_ALLOWED_EMAIL: allowedEmail,
  },
  stdio: "pipe",
});

server.stdout.on("data", (chunk) => process.stdout.write(chunk));
server.stderr.on("data", (chunk) => process.stderr.write(chunk));

try {
  await waitForServer(baseURL);
  const { chromium } = await import("playwright");
  const browser = await chromium.launch({ headless: true });

  try {
    await runScenario(
      browser,
      "transient account validation failure preserves stored API key",
      {
        status: 503,
        contentType: "application/json",
        body: JSON.stringify({ error: "temporarily unavailable" }),
      },
      apiKey
    );

    await runScenario(
      browser,
      "disallowed account email clears stored API key",
      {
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ userEmail: "someone-else@example.com" }),
      },
      null
    );
  } finally {
    await browser.close();
  }
} finally {
  server.kill();
}
