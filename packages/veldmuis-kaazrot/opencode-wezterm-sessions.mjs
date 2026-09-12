import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// Records which opencode session is live in each WezTerm pane so the
// terminal can resume the exact session per tab after a restart
// (including several tabs on the same folder).
// Map file: { "<pane_id>": { session, directory, updated } }

const STATE_DIR = join(
  process.env.XDG_STATE_HOME || join(process.env.HOME || "~", ".local/state"),
  "wezterm/resurrect",
);
const MAP_PATH = join(STATE_DIR, "opencode-sessions.json");
const MAX_ENTRIES = 200;
const MIN_WRITE_INTERVAL_MS = 10_000;

const lastWrite = new Map();

function paneIdFromEnvironment() {
  for (const name of ["OPENCODE_WEZTERM_PANE", "WEZTERM_PANE"]) {
    const value = process.env[name]?.trim();
    if (!value || !/^\d+$/.test(value)) continue;

    const paneId = Number(value);
    if (Number.isSafeInteger(paneId)) return String(paneId);
  }
}

function loadMap() {
  try {
    const parsed = JSON.parse(readFileSync(MAP_PATH, "utf8"));
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed;
  } catch {
    // Missing or corrupt map starts fresh.
  }
  return {};
}

function saveMap(map) {
  const entries = Object.entries(map);
  entries.sort((a, b) => (b[1]?.updated ?? 0) - (a[1]?.updated ?? 0));
  const pruned = Object.fromEntries(entries.slice(0, MAX_ENTRIES));
  mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(MAP_PATH, JSON.stringify(pruned));
}

export default async function opencodeWeztermSessions() {
  return {
    event: async ({ event }) => {
      // OpenCode 1.18.21 can deliver the newer event envelope with `data`;
      // older plugin SDKs use `properties`.
      const properties = event?.properties ?? event?.data;
      const sessionID = properties?.sessionID;
      if (typeof sessionID !== "string" || !/^ses_[A-Za-z0-9]+$/.test(sessionID)) return;

      const paneId = paneIdFromEnvironment();
      if (!paneId) return;

      const now = Date.now();
      const prev = lastWrite.get(paneId);
      if (prev && prev.session === sessionID && now - prev.at < MIN_WRITE_INTERVAL_MS) return;
      lastWrite.set(paneId, { session: sessionID, at: now });

      const map = loadMap();
      map[paneId] = { session: sessionID, directory: process.cwd(), updated: now };
      try {
        saveMap(map);
      } catch {
        // Session tracking must never break the session itself.
      }
    },
  };
}
