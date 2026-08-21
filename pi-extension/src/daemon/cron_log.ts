import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { remotePiHome } from "../paths.js";

/**
 * Append-only audit trail for cron fires at `~/.pi/remote/cron.jsonl`.
 *
 * One JSON line per scheduler decision — **every fire AND every skip** — so an
 * operator can see exactly what ran and what didn't (the agent's output goes
 * fire-and-forget to the relay/mesh, so the dispatch itself needs its own
 * trail). Plan/39 decision E.
 */

/** Outcome of a single `fireJob` decision. */
export type CronResult =
  | "delivered"
  | "deliver_failed"
  | "woke_and_delivered"
  | "skipped_busy"
  | "skipped_down"
  | "skipped_disabled";

export interface CronLogEntry {
  /** epoch ms */
  ts: number;
  job_id: string;
  daemon_id: string;
  schedule: string;
  /** true when a prompt was actually sent (delivered / woke_and_delivered). */
  fired: boolean;
  result: CronResult;
  /** First chars of the prompt, for at-a-glance log reading. */
  prompt_preview: string;
}

const PREVIEW_LEN = 80;

function logPath(): string {
  return join(remotePiHome(), "cron.jsonl");
}

/** Test/diag-only: the on-disk path. */
export function cronLogPath(): string {
  return logPath();
}

/** Maps a result to whether a prompt was actually delivered. */
export function firedFor(result: CronResult): boolean {
  return result === "delivered" || result === "woke_and_delivered";
}

/**
 * Appends one entry. Best-effort: creates the parent dir + file when absent;
 * never throws into the scheduler (a logging failure must not abort a fire).
 */
export function appendCronLog(
  entry: { job_id: string; daemon_id: string; schedule: string; result: CronResult; prompt: string },
): void {
  const line = JSON.stringify({
    ts: Date.now(),
    job_id: entry.job_id,
    daemon_id: entry.daemon_id,
    schedule: entry.schedule,
    fired: firedFor(entry.result),
    result: entry.result,
    prompt_preview: entry.prompt.slice(0, PREVIEW_LEN),
  } satisfies CronLogEntry) + "\n";
  try {
    mkdirSync(dirname(logPath()), { recursive: true });
    appendFileSync(logPath(), line, "utf8");
  } catch {
    /* audit is best-effort — don't break the scheduler on a write error */
  }
}

/**
 * Reads the log, newest-last. Optional `jobId` filter and `tail` (last N).
 * Missing file → []. Malformed lines are skipped.
 */
export function readCronLog(opts: { jobId?: string; tail?: number } = {}): CronLogEntry[] {
  if (!existsSync(logPath())) return [];
  let raw: string;
  try {
    raw = readFileSync(logPath(), "utf8");
  } catch {
    return [];
  }
  const entries: CronLogEntry[] = [];
  for (const line of raw.split("\n")) {
    if (!line.trim()) continue;
    try {
      const e = JSON.parse(line) as CronLogEntry;
      if (opts.jobId && e.job_id !== opts.jobId) continue;
      entries.push(e);
    } catch {
      /* skip malformed */
    }
  }
  if (opts.tail !== undefined && opts.tail >= 0 && entries.length > opts.tail) {
    return entries.slice(entries.length - opts.tail);
  }
  return entries;
}
