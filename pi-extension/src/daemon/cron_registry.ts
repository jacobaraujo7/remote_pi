import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { dirname, join } from "node:path";
import { Cron } from "croner";
import { remotePiHome } from "../paths.js";

/**
 * Cron registry: scheduled prompts for daemons, persisted at
 * `~/.pi/remote/cron.json`. Mirrors `registry.ts` (`daemons.json`) — tolerant
 * load (missing/corrupt → empty), atomic-ish full-file save.
 *
 * Each job targets a daemon by its `daemon_id` (the 8-hex id from
 * `daemonIdForCwd`) and fires `prompt` on `schedule` (a cron expression, run
 * by croner in the supervisor). The scheduler engine + `fireJob` live in
 * `supervisor.ts`; this module only owns persistence + schedule validation.
 *
 * Plan/39. Decisions B (croner), C (min-interval 60s), E (audit via cron_log).
 */

/** Minimum allowed interval between two consecutive runs of a schedule. */
export const MIN_INTERVAL_MS = 60_000;

/** A scheduled prompt. */
export interface CronJob {
  /** `j_<hex>` — random, stable across restarts. */
  id: string;
  /** Target daemon id (`daemonIdForCwd`). */
  daemon_id: string;
  /** Cron expression (croner syntax; optional 6th seconds field supported). */
  schedule: string;
  /** IANA timezone for the schedule (e.g. "America/Sao_Paulo"). */
  tz?: string;
  /** Prompt text injected into the daemon when the job fires. */
  prompt: string;
  enabled: boolean;
  /** Skip the fire when the daemon is mid-turn (default true). */
  skip_if_busy: boolean;
  /** Start the daemon if it's down, then fire (default false). */
  wake: boolean;
  /** On supervisor start, run once if the previous scheduled run was missed
   *  while it was down (default false; at most 1×). */
  catchup: boolean;
  created_at: string;
  last_run?: string;
  /** Last fire result — see cron_log `result` values. Shortcut for `cron list`. */
  last_status?: string;
}

export interface CronRegistry {
  jobs: CronJob[];
}

function cronPath(): string {
  return join(remotePiHome(), "cron.json");
}

/** Test/diag-only: the on-disk path. */
export function cronRegistryPath(): string {
  return cronPath();
}

/** Reads the registry; returns empty on missing/corrupt file. */
export function loadCronRegistry(): CronRegistry {
  if (!existsSync(cronPath())) return { jobs: [] };
  try {
    const parsed = JSON.parse(readFileSync(cronPath(), "utf8")) as unknown;
    if (!parsed || typeof parsed !== "object") return { jobs: [] };
    const arr = (parsed as { jobs?: unknown }).jobs;
    if (!Array.isArray(arr)) return { jobs: [] };
    const jobs: CronJob[] = [];
    for (const item of arr) {
      const job = _coerceJob(item);
      if (job) jobs.push(job);
    }
    return { jobs };
  } catch {
    return { jobs: [] };
  }
}

export function saveCronRegistry(reg: CronRegistry): void {
  mkdirSync(dirname(cronPath()), { recursive: true });
  writeFileSync(cronPath(), JSON.stringify(reg, null, 2) + "\n");
}

export function listJobs(): CronJob[] {
  return loadCronRegistry().jobs;
}

export function getJob(id: string): CronJob | undefined {
  return loadCronRegistry().jobs.find((j) => j.id === id);
}

/** Fields a caller supplies when creating a job. Flags default sensibly. */
export interface NewJobInput {
  daemon_id: string;
  schedule: string;
  prompt: string;
  tz?: string;
  skip_if_busy?: boolean;
  wake?: boolean;
  catchup?: boolean;
}

/** Adds a job with a fresh `j_<hex>` id. Pure persistence — call
 *  `validateSchedule` first at the op/CLI boundary. */
export function addJob(input: NewJobInput): CronJob {
  const reg = loadCronRegistry();
  const job: CronJob = {
    id: _freshId(reg.jobs),
    daemon_id: input.daemon_id,
    schedule: input.schedule,
    prompt: input.prompt,
    enabled: true,
    skip_if_busy: input.skip_if_busy ?? true,
    wake: input.wake ?? false,
    catchup: input.catchup ?? false,
    created_at: new Date().toISOString(),
  };
  if (input.tz) job.tz = input.tz;
  reg.jobs.push(job);
  saveCronRegistry(reg);
  return job;
}

export function removeJob(id: string): boolean {
  const reg = loadCronRegistry();
  const idx = reg.jobs.findIndex((j) => j.id === id);
  if (idx === -1) return false;
  reg.jobs.splice(idx, 1);
  saveCronRegistry(reg);
  return true;
}

export function setJobEnabled(id: string, enabled: boolean): boolean {
  const reg = loadCronRegistry();
  const job = reg.jobs.find((j) => j.id === id);
  if (!job) return false;
  job.enabled = enabled;
  saveCronRegistry(reg);
  return true;
}

/** Records the outcome of a fire on the job (the `cron list` shortcut). */
export function recordRun(id: string, at: string, status: string): void {
  const reg = loadCronRegistry();
  const job = reg.jobs.find((j) => j.id === id);
  if (!job) return;
  job.last_run = at;
  job.last_status = status;
  saveCronRegistry(reg);
}

// ── Schedule validation (croner) ────────────────────────────────────────────

export interface ScheduleValidation {
  ok: boolean;
  error?: string;
  /** Interval (ms) between the next two runs, when computable. */
  intervalMs?: number;
}

/**
 * Validates a cron expression via croner and enforces the ≥60s min-interval
 * (decision C — guards against pileup + token burn). Returns `ok:false` with a
 * user-facing message on a bad expression or a too-frequent schedule.
 */
export function validateSchedule(schedule: string, tz?: string): ScheduleValidation {
  let cron: Cron;
  try {
    cron = new Cron(schedule, tz ? { timezone: tz } : {});
  } catch (e) {
    return { ok: false, error: `invalid cron expression: ${(e as Error).message}` };
  }
  try {
    const n1 = cron.nextRun();
    const n2 = n1 ? cron.nextRun(n1) : null;
    if (!n1 || !n2) return { ok: false, error: "schedule has no upcoming runs" };
    const intervalMs = n2.getTime() - n1.getTime();
    if (intervalMs < MIN_INTERVAL_MS) {
      return {
        ok: false,
        intervalMs,
        error: `schedule too frequent: ~${Math.round(intervalMs / 1000)}s between runs (minimum is 60s)`,
      };
    }
    return { ok: true, intervalMs };
  } finally {
    cron.stop();
  }
}

/** Returns the next scheduled run for a job, or null. Used by `cron list`. */
export function nextRunFor(job: CronJob): Date | null {
  try {
    const cron = new Cron(job.schedule, job.tz ? { timezone: job.tz } : {});
    const n = cron.nextRun();
    cron.stop();
    return n;
  } catch {
    return null;
  }
}

// ── internals ───────────────────────────────────────────────────────────────

function _freshId(existing: CronJob[]): string {
  for (let i = 0; i < 1000; i++) {
    const id = `j_${randomBytes(4).toString("hex")}`;
    if (!existing.some((j) => j.id === id)) return id;
  }
  throw new Error("cron id space exhausted");
}

function _coerceJob(item: unknown): CronJob | null {
  if (!item || typeof item !== "object") return null;
  const o = item as Record<string, unknown>;
  if (typeof o["id"] !== "string") return null;
  if (typeof o["daemon_id"] !== "string") return null;
  if (typeof o["schedule"] !== "string") return null;
  if (typeof o["prompt"] !== "string") return null;
  const job: CronJob = {
    id: o["id"],
    daemon_id: o["daemon_id"],
    schedule: o["schedule"],
    prompt: o["prompt"],
    enabled: o["enabled"] !== false,
    skip_if_busy: o["skip_if_busy"] !== false,
    wake: o["wake"] === true,
    catchup: o["catchup"] === true,
    created_at: typeof o["created_at"] === "string" ? o["created_at"] : new Date(0).toISOString(),
  };
  if (typeof o["tz"] === "string") job.tz = o["tz"];
  if (typeof o["last_run"] === "string") job.last_run = o["last_run"];
  if (typeof o["last_status"] === "string") job.last_status = o["last_status"];
  return job;
}
