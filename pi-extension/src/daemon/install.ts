import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { delimiter } from "node:path";
import { homedir, platform, userInfo } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Generates and activates a system service for `pi-supervisord` so the
 * daemon fleet survives reboots (plan/26 W3).
 *
 * Platform support:
 *   - **macOS**: writes `~/Library/LaunchAgents/dev.remotepi.supervisord.plist`
 *     and runs `launchctl bootstrap gui/<uid> <plist>` (modern API) with a
 *     fallback to `launchctl load` for older macOS.
 *   - **Linux**: writes `~/.config/systemd/user/remote-pi-supervisord.service`
 *     and runs `systemctl --user daemon-reload && systemctl --user enable
 *     --now remote-pi-supervisord.service`.
 *
 * Uninstall reverses both. Idempotent — re-running install over an existing
 * unit refreshes it (paths could have changed if user moved node_modules).
 *
 * **What does NOT happen here**: the actual `npm install -g remote-pi` step.
 * The user has to make the supervisor bin reachable on disk before install
 * can wire up the service. The `findSupervisorScript` resolver detects
 * common cases (npm global, pnpm global, local dev clone) and yields a
 * clear error otherwise.
 */

// ── Platform detection ─────────────────────────────────────────────────────

export type SupervisorPlatform = "macos" | "linux" | "windows" | "unsupported";

export function detectPlatform(): SupervisorPlatform {
  switch (platform()) {
    case "darwin": return "macos";
    case "linux": return "linux";
    case "win32": return "windows";
    default: return "unsupported";
  }
}

// ── Path resolution ────────────────────────────────────────────────────────

/**
 * Absolute path to the supervisor's compiled entry. We resolve from
 * `import.meta.url` (this file's location) since wherever the daemon
 * module lives, `bin/supervisord.js` is a sibling of `daemon/` under
 * `dist/`.
 *
 * After build: `dist/daemon/install.js` → `dist/bin/supervisord.js`.
 * In dev (`tsx`): same path resolution still lands inside `src/`, which
 * isn't directly runnable by `node` — dev install isn't expected.
 */
export function findSupervisorScript(): string {
  const here = fileURLToPath(import.meta.url);          // dist/daemon/install.js
  const daemonDir = dirname(here);                       // dist/daemon
  const distRoot = dirname(daemonDir);                   // dist
  return resolve(distRoot, "bin/supervisord.js");
}

/**
 * Absolute path to the extension's CLI entry (`dist/index.js`). This is
 * the file we symlink to `~/.local/bin/remote-pi` so the user can run
 * `remote-pi <subcommand>` from any shell after installing the extension
 * through Pi (`pi install npm:remote-pi`).
 *
 * Same resolution strategy as `findSupervisorScript`: from
 * `dist/daemon/install.js` → `dist/index.js`.
 */
export function findRemotePiScript(): string {
  const here = fileURLToPath(import.meta.url);          // dist/daemon/install.js
  const daemonDir = dirname(here);                       // dist/daemon
  const distRoot = dirname(daemonDir);                   // dist
  return resolve(distRoot, "index.js");
}

export function findNodeBinary(): string {
  // `process.execPath` is always absolute and points at the current Node
  // binary. Embedding it in the service unit means the user gets the
  // exact same Node version they invoked `remote-pi install` with — no
  // PATH ambiguity at boot time.
  return process.execPath;
}

export function findTemplate(name: "systemd" | "launchd" | "taskscheduler"): string {
  // Templates ship next to the compiled `dist/` (via `files` in package.json).
  // From `dist/daemon/install.js` go up two levels and into
  // `service-templates/`. In the published npm tarball the layout is the
  // same — `service-templates/` is sibling to `dist/`.
  const here = fileURLToPath(import.meta.url);          // dist/daemon/install.js
  const pkgRoot = resolve(dirname(dirname(dirname(here))));  // package root
  const file =
    name === "systemd" ? "systemd.service.template" :
    name === "launchd" ? "launchd.plist.template" :
    "task-scheduler.xml.template";
  return resolve(pkgRoot, "service-templates", file);
}

// ── Service paths ──────────────────────────────────────────────────────────

export function systemdUnitPath(): string {
  return join(homedir(), ".config", "systemd", "user", "remote-pi-supervisord.service");
}

export function launchdPlistPath(): string {
  return join(homedir(), "Library", "LaunchAgents", "dev.remotepi.supervisord.plist");
}

export const LAUNCHD_LABEL = "dev.remotepi.supervisord";
/** systemd --user unit name (with `.service`) for the supervisor. */
export const SYSTEMD_UNIT = "remote-pi-supervisord.service";
/** Windows Task Scheduler task name (plan/40). */
export const WINDOWS_TASK_NAME = "RemotePiSupervisor";

/** Path of the rendered Task Scheduler XML (input to `schtasks /Create /XML`). */
export function taskXmlPath(): string {
  return join(homedir(), ".pi", "remote", "RemotePiSupervisor.xml");
}

// ── Template rendering ─────────────────────────────────────────────────────

export interface RenderVars {
  node: string;
  supervisor: string;
  home: string;
  user: string;
  /** PATH inherited so `pi --mode rpc` resolves the same way it does
   *  interactively. We snapshot `process.env.PATH` at install time. */
  path: string;
}

export function defaultRenderVars(): RenderVars {
  return {
    node: findNodeBinary(),
    supervisor: findSupervisorScript(),
    home: homedir(),
    user: userInfo().username,
    path: process.env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin",
  };
}

/** Replace `{NODE}` / `{SUPERVISOR}` / `{USER}` / `{HOME}` / `{PATH}`. */
export function renderTemplate(template: string, vars: RenderVars): string {
  return template
    .replace(/\{NODE\}/g, vars.node)
    .replace(/\{SUPERVISOR\}/g, vars.supervisor)
    .replace(/\{USER\}/g, vars.user)
    .replace(/\{HOME\}/g, vars.home)
    .replace(/\{PATH\}/g, vars.path);
}

// ── Install / uninstall API ────────────────────────────────────────────────

export interface InstallResult {
  platform: SupervisorPlatform;
  unitPath: string;
  /** Lines describing each step taken — surfaced to the user via notify. */
  log: string[];
}

/**
 * Writes the unit/plist, runs the platform's activation command. Throws
 * on unsupported OS or when the supervisor script isn't found.
 *
 * Idempotent: re-running re-writes the unit (paths could have changed)
 * and re-activates via the platform tool's idempotent flag.
 */
export function installService(vars: RenderVars = defaultRenderVars()): InstallResult {
  const plat = detectPlatform();
  const log: string[] = [];

  if (plat === "unsupported") {
    throw new Error(`unsupported platform: ${platform()}. Only macOS and Linux.`);
  }

  // Sanity: supervisor script must exist on disk.
  if (!existsSync(vars.supervisor)) {
    throw new Error(
      `supervisor script not found at ${vars.supervisor}. ` +
      "Run `pnpm build` (dev) or `npm install -g remote-pi` (prod) first.",
    );
  }

  const templateName = plat === "macos" ? "launchd" : plat === "linux" ? "systemd" : "taskscheduler";
  const templatePath = findTemplate(templateName);
  if (!existsSync(templatePath)) {
    throw new Error(`service template missing: ${templatePath}`);
  }
  const tpl = readFileSync(templatePath, "utf8");
  const rendered = renderTemplate(tpl, vars);

  const unitPath = plat === "macos" ? launchdPlistPath() : plat === "linux" ? systemdUnitPath() : taskXmlPath();
  mkdirSync(dirname(unitPath), { recursive: true });
  if (plat === "windows") {
    // `schtasks /Create /XML` requires UTF-16LE + BOM. A UTF-8 file fails with
    // "(1,40)::ERROR: unable to switch the encoding" — the bytes must match the
    // template's `encoding="UTF-16"` declaration. (plan/40 risk #5.)
    const bom = Buffer.from([0xff, 0xfe]); // UTF-16LE byte-order mark
    writeFileSync(unitPath, Buffer.concat([bom, Buffer.from(rendered, "utf16le")]));
  } else {
    writeFileSync(unitPath, rendered);  // launchd/systemd → UTF-8
  }
  log.push(`wrote ${unitPath}`);

  if (plat === "macos") {
    // Unload first in case a stale entry exists from a prior install —
    // `launchctl bootstrap` errors out otherwise. `bootout` is the modern
    // API; `unload` is the legacy fallback. Either may fail silently.
    const uid = userInfo().uid;
    _tryExec("launchctl", ["bootout", `gui/${uid}`, unitPath], log);
    _tryExec("launchctl", ["unload", unitPath], log);
    _exec("launchctl", ["bootstrap", `gui/${uid}`, unitPath], log);
    log.push(`activated via launchctl bootstrap gui/${uid}`);
  } else if (plat === "linux") {
    _exec("systemctl", ["--user", "daemon-reload"], log);
    _exec("systemctl", ["--user", "enable", "--now", "remote-pi-supervisord.service"], log);
    log.push("activated via systemctl --user enable --now");
  } else {
    // windows — Task Scheduler (plan/40). End any prior instance, (re)create
    // the task from the rendered XML (user-level, restart-on-failure), run now.
    _tryExec("schtasks", ["/End", "/TN", WINDOWS_TASK_NAME], log);
    _exec("schtasks", ["/Create", "/XML", unitPath, "/TN", WINDOWS_TASK_NAME, "/F"], log);
    _exec("schtasks", ["/Run", "/TN", WINDOWS_TASK_NAME], log);
    log.push(`activated via schtasks /Create + /Run (${WINDOWS_TASK_NAME})`);
  }

  return { platform: plat, unitPath, log };
}

export interface UninstallResult {
  platform: SupervisorPlatform;
  unitPath: string;
  removed: boolean;
  log: string[];
}

export function uninstallService(): UninstallResult {
  const plat = detectPlatform();
  const log: string[] = [];

  if (plat === "unsupported") {
    throw new Error(`unsupported platform: ${platform()}. Only macOS and Linux.`);
  }

  const unitPath = plat === "macos" ? launchdPlistPath() : plat === "linux" ? systemdUnitPath() : taskXmlPath();

  if (plat === "macos") {
    const uid = userInfo().uid;
    _tryExec("launchctl", ["bootout", `gui/${uid}`, unitPath], log);
    _tryExec("launchctl", ["unload", unitPath], log);
    log.push("deactivated via launchctl bootout");
  } else if (plat === "linux") {
    _tryExec("systemctl", ["--user", "disable", "--now", "remote-pi-supervisord.service"], log);
    log.push("deactivated via systemctl --user disable --now");
  } else {
    // windows — Task Scheduler (plan/40): stop + delete the task.
    _tryExec("schtasks", ["/End", "/TN", WINDOWS_TASK_NAME], log);
    _tryExec("schtasks", ["/Delete", "/TN", WINDOWS_TASK_NAME, "/F"], log);
    log.push(`deactivated via schtasks /Delete (${WINDOWS_TASK_NAME})`);
  }

  let removed = false;
  if (existsSync(unitPath)) {
    try { unlinkSync(unitPath); removed = true; log.push(`removed ${unitPath}`); }
    catch (e) { log.push(`failed to remove ${unitPath}: ${String(e)}`); }
  }

  if (plat === "linux") {
    _tryExec("systemctl", ["--user", "daemon-reload"], log);
  }

  // Hint about the label for users that want to verify manually.
  if (plat === "macos") log.push(`(label: ${LAUNCHD_LABEL})`);

  return { platform: plat, unitPath, removed, log };
}

// ── Internals ──────────────────────────────────────────────────────────────

function _exec(cmd: string, args: string[], log: string[]): void {
  try {
    const out = execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    if (out.trim()) log.push(`$ ${cmd} ${args.join(" ")}\n${out.trim()}`);
    else log.push(`$ ${cmd} ${args.join(" ")}`);
  } catch (e) {
    const err = e as { stderr?: Buffer | string; status?: number; message: string };
    const stderr = typeof err.stderr === "string" ? err.stderr : err.stderr?.toString() ?? "";
    throw new Error(
      `\`${cmd} ${args.join(" ")}\` exited ${err.status ?? "?"}\n${stderr.trim() || err.message}`,
    );
  }
}

/** Like _exec but swallows errors — used for cleanup steps where failure
 *  is expected (e.g., "unload" before "load" when nothing was loaded). */
function _tryExec(cmd: string, args: string[], log: string[]): void {
  try { _exec(cmd, args, log); } catch { /* expected, suppress */ }
}

// ── CLI bin linking (plan/27) ─────────────────────────────────────────────────
//
// When the user installs Remote Pi through Pi (`pi install npm:remote-pi`),
// the extension's `bin` entries in package.json never reach `$PATH` — Pi's
// installer ignores them. Without `npm install -g remote-pi` a second time,
// the user can't run `remote-pi daemon …` from a shell.
//
// `linkCliBinaries` writes two symlinks into `~/.local/bin/`:
//   - `remote-pi`     → `<extensionRoot>/dist/index.js`
//   - `pi-supervisord`→ `<extensionRoot>/dist/bin/supervisord.js`
//
// Both targets get `chmod +x` (tsc doesn't preserve the executable bit;
// node tolerates running them via symlink either way, but POSIX shells
// won't `exec` a non-executable file directly).
//
// This step is opt-in and runs ONLY when the slash-command path triggers
// `_cmdInstall` — i.e., the user is inside Pi's TUI. The CLI-mode path
// (`remote-pi install` invoked from a shell because the user did
// `npm install -g remote-pi`) MUST NOT symlink — the user already has
// working bins from npm-global, and stomping them with our symlinks
// would point them at the *Pi-extension copy* instead of the npm-global
// copy, which is a different file tree and would diverge on upgrades.

export interface LinkBinariesResult {
  /** `~/.local/bin/`. The two symlinks land here. */
  binDir: string;
  /** Paths of the two symlinks we created/refreshed. */
  links: Array<{ name: string; path: string; target: string }>;
  /** True when `binDir` is already on `$PATH`. False → caller surfaces the
   *  "add this line to your shell rc" hint to the user. */
  onPath: boolean;
  log: string[];
}

export function userLocalBinDir(home: string = homedir()): string {
  return join(home, ".local", "bin");
}

/**
 * Check whether `dir` is on `process.env.PATH`. Tolerates trailing
 * slashes and relative entries (which we treat as not matching — `~/.local/bin`
 * is always absolute on our end).
 */
export function isOnPath(dir: string, envPath: string = process.env["PATH"] ?? ""): boolean {
  const target = dir.replace(/\/+$/, "");
  return envPath.split(delimiter).some((entry) => entry.replace(/\/+$/, "") === target);
}

/**
 * Create (or refresh) the `remote-pi` + `pi-supervisord` symlinks in
 * `~/.local/bin/`. Idempotent — replaces stale links pointing at old
 * extension paths (Pi can reinstall the extension to a different hash dir
 * on upgrades, so this MUST overwrite).
 *
 * Returns `onPath: false` when `~/.local/bin` isn't in the user's `$PATH`.
 * The caller is responsible for surfacing the shell-rc instruction —
 * we don't edit the user's shell config files automatically.
 */
export function linkCliBinaries(
  home: string = homedir(),
  paths: { remotePi?: string; supervisord?: string } = {},
): LinkBinariesResult {
  const binDir = userLocalBinDir(home);

  // Windows (plan/40): no POSIX symlinks / `~/.local/bin`. The supported path
  // is `npm install -g remote-pi`, which provides the `remote-pi` /
  // `pi-supervisord` command shims (`.cmd`) on PATH. Skip linking, don't fail.
  if (platform() === "win32") {
    return {
      binDir,
      links: [],
      onPath: true,
      log: ["Windows: skipping CLI symlinks — `npm install -g remote-pi` provides the command shims."],
    };
  }

  const log: string[] = [];

  mkdirSync(binDir, { recursive: true });
  log.push(`ensured ${binDir}`);

  const remotePi = paths.remotePi ?? findRemotePiScript();
  const supervisord = paths.supervisord ?? findSupervisorScript();
  if (!existsSync(remotePi)) {
    throw new Error(
      `remote-pi script not found at ${remotePi}. ` +
      "Run `pnpm build` (dev) or reinstall the extension.",
    );
  }
  if (!existsSync(supervisord)) {
    throw new Error(
      `supervisor script not found at ${supervisord}. ` +
      "Run `pnpm build` (dev) or reinstall the extension.",
    );
  }

  // tsc strips the executable bit on its outputs; the shebang at the top
  // of dist/index.js means the file IS a valid interpreter target once
  // chmod +x is applied. Same for supervisord.js (no shebang — we rely
  // on `node` resolving via the symlink at exec time).
  try { chmodSync(remotePi, 0o755); } catch { /* best-effort */ }
  try { chmodSync(supervisord, 0o755); } catch { /* best-effort */ }

  const links: LinkBinariesResult["links"] = [
    { name: "remote-pi",     path: join(binDir, "remote-pi"),      target: remotePi },
    { name: "pi-supervisord", path: join(binDir, "pi-supervisord"), target: supervisord },
  ];
  for (const link of links) {
    _replaceSymlink(link.path, link.target, log);
  }

  const onPath = isOnPath(binDir);
  if (!onPath) {
    log.push(
      `WARNING: ${binDir} is not on $PATH. ` +
      `Add this line to your shell rc (~/.zshrc, ~/.bashrc, etc.): ` +
      `export PATH="$HOME/.local/bin:$PATH"`,
    );
  }

  return { binDir, links, onPath, log };
}

/**
 * Remove the symlinks `linkCliBinaries` created. Idempotent — missing
 * links are a no-op. Returns whether each link was actually present so
 * the caller can render a useful summary. Targets (the extension files)
 * are NOT touched here — they live outside this dir and belong to Pi.
 */
export interface UnlinkBinariesResult {
  binDir: string;
  removed: Array<{ name: string; path: string; existed: boolean }>;
  log: string[];
}

export function unlinkCliBinaries(home: string = homedir()): UnlinkBinariesResult {
  const binDir = userLocalBinDir(home);
  const log: string[] = [];
  const names = ["remote-pi", "pi-supervisord"];
  const removed: UnlinkBinariesResult["removed"] = [];

  for (const name of names) {
    const path = join(binDir, name);
    let existed = false;
    try {
      // lstatSync (not stat) so a symlink targeting a deleted file still
      // resolves — we want to remove the LINK itself, not chase it.
      lstatSync(path);
      existed = true;
    } catch { /* not present */ }
    if (existed) {
      try {
        unlinkSync(path);
        log.push(`removed ${path}`);
      } catch (e) {
        log.push(`failed to remove ${path}: ${String(e)}`);
        existed = false;
      }
    }
    removed.push({ name, path, existed });
  }

  return { binDir, removed, log };
}

/**
 * Atomic-ish symlink replace. Idiomatic recipe — `symlinkSync` errors
 * with `EEXIST` if the path is already a symlink/file, so we remove
 * first. Race window between unlink and symlink is irrelevant for a
 * single-user install command (no concurrent writers).
 */
function _replaceSymlink(linkPath: string, target: string, log: string[]): void {
  let existing: string | null = null;
  try {
    existing = readlinkSync(linkPath);
  } catch { /* not a symlink, or doesn't exist */ }

  if (existing === target) {
    log.push(`symlink ${linkPath} → ${target} (unchanged)`);
    return;
  }

  // Either it doesn't exist, or it points elsewhere. Remove + recreate.
  try { unlinkSync(linkPath); } catch { /* fine if absent */ }
  symlinkSync(target, linkPath);
  log.push(`symlink ${linkPath} → ${target}`);
}
