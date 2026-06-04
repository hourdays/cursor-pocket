#!/usr/bin/env node
/**
 * Records web/?demo=1 walkthrough to /opt/cursor/artifacts/cursor-pocket-demo.webm
 * Requires: dev server on :5173, npx playwright chromium
 */
import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outDir = "/opt/cursor/artifacts";
const videoDir = path.join(outDir, "demo-video-raw");

async function waitForServer(url, ms = 60000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    try {
      const r = await fetch(url);
      if (r.ok) return;
    } catch {
      /* retry */
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  throw new Error(`Server not up: ${url}`);
}

function run(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: "inherit", ...opts });
    p.on("exit", (code) =>
      code === 0 ? resolve() : reject(new Error(`${cmd} exited ${code}`))
    );
  });
}

const { chromium } = await import("playwright");

await mkdir(outDir, { recursive: true });
await mkdir(videoDir, { recursive: true });

await waitForServer("http://127.0.0.1:5173/");

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  recordVideo: { dir: videoDir, size: { width: 1280, height: 800 } },
});
const page = await context.newPage();
await page.goto("http://127.0.0.1:5173/?demo=1", { waitUntil: "networkidle" });
await page.waitForTimeout(14000);
await context.close();
await browser.close();

const { readdir } = await import("node:fs/promises");
const files = await readdir(videoDir);
const webmName = files.find((f) => f.endsWith(".webm"));
if (!webmName) {
  throw new Error("No webm in " + videoDir);
}

const rawPath = path.join(videoDir, webmName);
const mp4Path = path.join(outDir, "cursor-pocket-demo.mp4");

await run("ffmpeg", [
  "-y",
  "-i",
  rawPath,
  "-c:v",
  "libx264",
  "-pix_fmt",
  "yuv420p",
  "-movflags",
  "+faststart",
  mp4Path,
]);

console.log("Wrote", mp4Path);
