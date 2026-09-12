import { spawn } from "node:child_process";

const sessionStates = new Map();
let lastTimestamp = 0;

function uniqueTimestamp() {
  const now = Date.now();
  lastTimestamp = Math.max(now, lastTimestamp + 1);
  return String(lastTimestamp);
}

function paneIdFromEnvironment() {
  for (const name of ["OPENCODE_WEZTERM_PANE", "WEZTERM_PANE"]) {
    const value = process.env[name]?.trim();
    if (!value || !/^\d+$/.test(value)) continue;

    const paneId = Number(value);
    if (Number.isSafeInteger(paneId)) return String(paneId);
  }
}

function sendState(paneId, state) {
  if (!paneId) return Promise.resolve();

  const title = `__OPENCODE_ATTENTION__:${state}`;

  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(
        "wezterm",
        ["cli", "set-tab-title", "--pane-id", paneId, title],
        { stdio: "ignore" },
      );
    } catch {
      resolve();
      return;
    }

    child.once("error", resolve);
    child.once("close", resolve);
  });
}

function stateFor(sessionID) {
  let state = sessionStates.get(sessionID);
  if (!state) {
    state = {
      active: false,
      errorObserved: false,
      errorEmitted: false,
      paneId: undefined,
    };
    sessionStates.set(sessionID, state);
  }
  return state;
}

function paneFor(state) {
  if (!state.paneId) state.paneId = paneIdFromEnvironment();
  return state.paneId;
}

async function finishSession(state) {
  state.active = false;
  const paneId = paneFor(state);

  if (state.errorObserved) {
    if (!state.errorEmitted) {
      state.errorEmitted = true;
      await sendState(paneId, `error:${uniqueTimestamp()}`);
    }
  } else {
    await sendState(paneId, `done:${uniqueTimestamp()}`);
  }
}

export default async function opencodeWeztermAttention() {
  return {
    event: async ({ event }) => {
      // OpenCode 1.18.21 can deliver the newer event envelope with `data`;
      // older plugin SDKs use `properties`.
      const properties = event?.properties ?? event?.data;
      const sessionID = properties?.sessionID;
      if (typeof sessionID !== "string" || sessionID.length === 0) return;

      if (event.type === "session.status") {
        const status = properties.status?.type;
        const state = stateFor(sessionID);

        if (status === "busy") {
          const newRun = !state.active;
          state.active = true;
          if (newRun) {
            state.errorObserved = false;
            state.errorEmitted = false;
          }

          // A non-done value clears any completion left by an earlier run.
          await sendState(paneFor(state), `busy:${uniqueTimestamp()}`);
          return;
        }

        if (status !== "idle" || !state.active) return;

        await finishSession(state);
        sessionStates.delete(sessionID);
        return;
      }

      if (event.type === "session.idle") {
        const state = stateFor(sessionID);
        if (!state.active) return;

        await finishSession(state);
        sessionStates.delete(sessionID);
        return;
      }

      if (event.type === "session.error") {
        const state = stateFor(sessionID);
        state.errorObserved = true;
        state.errorEmitted = true;
        await sendState(paneFor(state), `error:${uniqueTimestamp()}`);
      }
    },
  };
}
