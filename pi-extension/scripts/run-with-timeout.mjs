import { spawn } from "node:child_process";

const [secondsArgument, command, ...args] = process.argv.slice(2);
const seconds = Number(secondsArgument);

if (!Number.isFinite(seconds) || seconds <= 0 || !command) {
  process.stderr.write("Usage: node scripts/run-with-timeout.mjs <seconds> <command> [args…]\n");
  process.exit(2);
}

let finished = false;
let timedOut = false;
let hardKillTimer;
let forceExitTimer;

const child = spawn(command, args, { stdio: "inherit", shell: false });
const timeoutTimer = setTimeout(() => {
  timedOut = true;
  process.stderr.write(`Command timed out after ${seconds}s: ${command}\n`);
  try { child.kill("SIGTERM"); } catch { /* child already exited */ }
  hardKillTimer = setTimeout(() => {
    try { child.kill("SIGKILL"); } catch { /* child already exited */ }
  }, 1_000);
  forceExitTimer = setTimeout(() => process.exit(124), 2_000);
}, seconds * 1_000);

function finish(exitCode) {
  if (finished) return;
  finished = true;
  clearTimeout(timeoutTimer);
  if (hardKillTimer) clearTimeout(hardKillTimer);
  if (forceExitTimer) clearTimeout(forceExitTimer);
  process.exitCode = exitCode;
}

child.once("error", (error) => {
  process.stderr.write(`Could not start ${command}: ${error.message}\n`);
  finish(timedOut ? 124 : error.code === "ENOENT" ? 127 : 1);
});

child.once("exit", (code, signal) => {
  finish(timedOut ? 124 : code ?? (signal ? 1 : 0));
});
