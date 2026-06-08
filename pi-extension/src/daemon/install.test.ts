import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { existsSync, lstatSync, mkdtempSync, readFileSync, readlinkSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join } from "node:path";

/** POSIX-only describes: features the Bloco C (plan/40) intentionally skips on
 *  Windows (symlinks/`~/.local/bin`, systemd, launchd). */
const posixOnly = process.platform === "win32";
import {
  defaultRenderVars,
  detectPlatform,
  findNodeBinary,
  findSupervisorScript,
  findRemotePiScript,
  findTemplate,
  isOnPath,
  launchdPlistPath,
  linkCliBinaries,
  renderTemplate,
  systemdUnitPath,
  unlinkCliBinaries,
  userLocalBinDir,
} from "./install.js";

/**
 * Pure-function tests for the install module. We do NOT exercise the
 * actual `launchctl`/`systemctl` calls — those are platform-specific +
 * change real OS state. The smoke test for activation is documented in
 * the README and run manually.
 */

describe("detectPlatform", () => {
  test("returns a known platform", () => {
    const p = detectPlatform();
    expect(["macos", "linux", "windows", "unsupported"]).toContain(p);
  });
});

describe("findNodeBinary", () => {
  test("returns process.execPath (absolute)", () => {
    expect(findNodeBinary()).toBe(process.execPath);
    expect(isAbsolute(findNodeBinary())).toBe(true); // `/...` POSIX, `C:\...` win32
  });
});

describe("findSupervisorScript", () => {
  test("ends with bin/supervisord.js (whatever distRoot is)", () => {
    // `join` yields the platform separator (`/` POSIX, `\` win32).
    expect(findSupervisorScript().endsWith(join("bin", "supervisord.js"))).toBe(true);
  });
});

describe("findTemplate", () => {
  test("systemd template file exists on disk", () => {
    const p = findTemplate("systemd");
    expect(p.endsWith("systemd.service.template")).toBe(true);
    // The file should be readable from this project's checkout (tests
    // run from pi-extension/, and templates live next to dist/).
    const content = readFileSync(p, "utf8");
    expect(content).toContain("[Service]");
    expect(content).toContain("{NODE}");
    expect(content).toContain("{SUPERVISOR}");
  });

  test("launchd template file exists on disk", () => {
    const p = findTemplate("launchd");
    expect(p.endsWith("launchd.plist.template")).toBe(true);
    const content = readFileSync(p, "utf8");
    expect(content).toContain("<key>Label</key>");
    expect(content).toContain("dev.remotepi.supervisord");
    expect(content).toContain("{NODE}");
    expect(content).toContain("{SUPERVISOR}");
  });

  test("task-scheduler (Windows) template file exists on disk (plan/40)", () => {
    const p = findTemplate("taskscheduler");
    expect(p.endsWith("task-scheduler.xml.template")).toBe(true);
    const content = readFileSync(p, "utf8");
    expect(content).toContain("<Task ");
    expect(content).toContain("<LogonTrigger>");
    expect(content).toContain("<RestartOnFailure>");
    expect(content).toContain("{NODE}");
    expect(content).toContain("{SUPERVISOR}");
    // Must declare UTF-16 to match the UTF-16LE+BOM bytes install.ts writes —
    // schtasks /Create /XML rejects a mismatch ("unable to switch the encoding").
    expect(content).toContain('encoding="UTF-16"');
  });
});

describe("renderTemplate", () => {
  const vars = {
    node: "/usr/local/bin/node",
    supervisor: "/Users/x/dist/bin/supervisord.js",
    home: "/Users/x",
    user: "jacob",
    path: "/usr/local/bin:/usr/bin:/bin",
  };

  test("substitutes every placeholder in systemd template", () => {
    const tpl = readFileSync(findTemplate("systemd"), "utf8");
    const out = renderTemplate(tpl, vars);
    expect(out).not.toContain("{NODE}");
    expect(out).not.toContain("{SUPERVISOR}");
    expect(out).not.toContain("{HOME}");
    expect(out).not.toContain("{PATH}");
    expect(out).not.toContain("{USER}");
    expect(out).toContain(vars.node);
    expect(out).toContain(vars.supervisor);
    expect(out).toContain(vars.home);
    expect(out).toContain(vars.path);
  });

  test("substitutes every placeholder in launchd template", () => {
    const tpl = readFileSync(findTemplate("launchd"), "utf8");
    const out = renderTemplate(tpl, vars);
    expect(out).not.toContain("{NODE}");
    expect(out).not.toContain("{SUPERVISOR}");
    expect(out).not.toContain("{HOME}");
    expect(out).not.toContain("{PATH}");
    expect(out).toContain(`<string>${vars.node}</string>`);
    expect(out).toContain(`<string>${vars.supervisor}</string>`);
    expect(out).toContain(`<string>${vars.home}/.pi/remote/supervisord.log</string>`);
  });

  test("global replacement (multiple occurrences of same placeholder)", () => {
    // HOME appears in multiple keys of the launchd plist.
    const tpl = readFileSync(findTemplate("launchd"), "utf8");
    const out = renderTemplate(tpl, vars);
    // No unsubstituted {HOME} anywhere.
    expect(out.match(/\{HOME\}/g)).toBeNull();
    // And the value appears more than once (logs + EnvironmentVariables).
    const matches = out.match(new RegExp(vars.home.replace(/[/.]/g, "\\$&"), "g"));
    expect(matches && matches.length > 1).toBe(true);
  });
});

// systemd/launchd paths are POSIX-only (Windows uses Task Scheduler — plan/40).
describe.skipIf(posixOnly)("paths", () => {
  test("systemdUnitPath lives under ~/.config/systemd/user/", () => {
    expect(systemdUnitPath()).toMatch(/\.config\/systemd\/user\/remote-pi-supervisord\.service$/);
  });

  test("launchdPlistPath lives under ~/Library/LaunchAgents/", () => {
    expect(launchdPlistPath()).toMatch(/Library\/LaunchAgents\/dev\.remotepi\.supervisord\.plist$/);
  });
});

describe("defaultRenderVars", () => {
  test("populates all required fields", () => {
    const vars = defaultRenderVars();
    expect(vars.node).toBe(process.execPath);
    expect(vars.supervisor.endsWith(join("bin", "supervisord.js"))).toBe(true);
    expect(isAbsolute(vars.home)).toBe(true);
    expect(vars.user.length).toBeGreaterThan(0);
    expect(vars.path.length).toBeGreaterThan(0);
  });
});

// ── CLI bin linking (plan/27) ────────────────────────────────────────────────

describe("findRemotePiScript", () => {
  test("resolves to dist/index.js sibling of supervisord", () => {
    const p = findRemotePiScript();
    expect(basename(p)).toBe("index.js");
    // Same dist root as supervisord: dirname(index.js) === dirname(dist/bin).
    expect(dirname(p)).toBe(dirname(dirname(findSupervisorScript())));
  });
});

// `~/.local/bin` + `:`-delimited PATH are POSIX-only (Windows skips CLI symlinks).
describe.skipIf(posixOnly)("userLocalBinDir + isOnPath", () => {
  test("userLocalBinDir composes ~/.local/bin from given homedir", () => {
    expect(userLocalBinDir("/tmp/fakehome")).toBe("/tmp/fakehome/.local/bin");
  });

  test("isOnPath matches dirs with and without trailing slash", () => {
    expect(isOnPath("/x/.local/bin", "/usr/bin:/x/.local/bin:/opt/bin")).toBe(true);
    expect(isOnPath("/x/.local/bin", "/usr/bin:/x/.local/bin/:/opt/bin")).toBe(true);
    expect(isOnPath("/x/.local/bin/", "/usr/bin:/x/.local/bin")).toBe(true);
    expect(isOnPath("/x/.local/bin", "/usr/bin:/opt/bin")).toBe(false);
    expect(isOnPath("/x/.local/bin", "")).toBe(false);
  });
});

// CLI symlinks are POSIX-only — linkCliBinaries returns early on Windows
// (npm-global provides the `.cmd` shims there), so these don't apply.
describe.skipIf(posixOnly)("linkCliBinaries / unlinkCliBinaries", () => {
  let tmpHome: string;
  let fakePaths: { remotePi: string; supervisord: string };

  beforeEach(() => {
    tmpHome = mkdtempSync(join(tmpdir(), "pi-link-"));
    // Stand-ins for the real extension files so the test doesn't depend
    // on `pnpm build` having run.
    const stub = join(tmpHome, "fake-ext");
    mkdirSync(join(stub, "bin"), { recursive: true });
    fakePaths = {
      remotePi: join(stub, "index.js"),
      supervisord: join(stub, "bin", "supervisord.js"),
    };
    writeFileSync(fakePaths.remotePi, "#!/usr/bin/env node\n");
    writeFileSync(fakePaths.supervisord, "#!/usr/bin/env node\n");
  });

  afterEach(() => {
    rmSync(tmpHome, { recursive: true, force: true });
  });

  test("link creates two symlinks pointing at the real extension files", () => {
    const result = linkCliBinaries(tmpHome, fakePaths);
    expect(result.binDir).toBe(join(tmpHome, ".local", "bin"));
    expect(result.links).toHaveLength(2);

    const names = result.links.map((l) => l.name).sort();
    expect(names).toEqual(["pi-supervisord", "remote-pi"]);

    for (const link of result.links) {
      expect(lstatSync(link.path).isSymbolicLink()).toBe(true);
      expect(readlinkSync(link.path)).toBe(link.target);
    }
  });

  test("link is idempotent (re-running yields same symlinks, no error)", () => {
    linkCliBinaries(tmpHome, fakePaths);
    const second = linkCliBinaries(tmpHome, fakePaths);
    for (const link of second.links) {
      expect(readlinkSync(link.path)).toBe(link.target);
    }
    // The "unchanged" branch should have fired the second time.
    expect(second.log.some((l) => l.includes("(unchanged)"))).toBe(true);
  });

  test("link replaces a stale symlink pointing elsewhere", () => {
    const binDir = join(tmpHome, ".local", "bin");
    mkdirSync(binDir, { recursive: true });
    // Write a fake stale symlink first
    const stale = join(binDir, "remote-pi");
    writeFileSync(join(tmpHome, "fake-old.js"), "// old\n");
    require("node:fs").symlinkSync(join(tmpHome, "fake-old.js"), stale);
    expect(readlinkSync(stale)).toBe(join(tmpHome, "fake-old.js"));

    const result = linkCliBinaries(tmpHome, fakePaths);
    const pi = result.links.find((l) => l.name === "remote-pi")!;
    expect(readlinkSync(pi.path)).toBe(pi.target);
    expect(readlinkSync(pi.path)).not.toBe(join(tmpHome, "fake-old.js"));
  });

  test("link signals onPath=false when binDir is absent from PATH (typical CI)", () => {
    const originalPath = process.env["PATH"];
    process.env["PATH"] = "/usr/bin:/bin";
    try {
      const result = linkCliBinaries(tmpHome, fakePaths);
      expect(result.onPath).toBe(false);
      expect(result.log.some((l) => l.includes("not on $PATH"))).toBe(true);
    } finally {
      process.env["PATH"] = originalPath;
    }
  });

  test("unlink removes both symlinks, idempotent on second call", () => {
    linkCliBinaries(tmpHome, fakePaths);
    const first = unlinkCliBinaries(tmpHome);
    expect(first.removed.map((r) => r.existed)).toEqual([true, true]);
    for (const r of first.removed) {
      expect(existsSync(r.path)).toBe(false);
    }
    // Second call is a no-op
    const second = unlinkCliBinaries(tmpHome);
    expect(second.removed.map((r) => r.existed)).toEqual([false, false]);
  });

  test("unlink does NOT delete the extension files (link targets are preserved)", () => {
    const linkResult = linkCliBinaries(tmpHome, fakePaths);
    unlinkCliBinaries(tmpHome);
    for (const link of linkResult.links) {
      // The target file (the actual dist/index.js etc) still exists.
      expect(existsSync(link.target)).toBe(true);
    }
  });
});
