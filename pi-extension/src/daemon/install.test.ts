import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { existsSync, lstatSync, mkdtempSync, readFileSync, readlinkSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join } from "node:path";

/** POSIX-only describes: features the Bloco C (plan/40) intentionally skips on
 *  Windows (symlinks/`~/.local/bin`, systemd, launchd). */
const posixOnly = process.platform === "win32";
import {
  buildCmdShim,
  buildElevatedCmd,
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
  vbsLauncherPath,
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
    // {NODE}/{SUPERVISOR} now live in the VBS launcher, not the XML — the XML's
    // action invokes wscript.exe with {VBS} (asserted below).
    // Must declare UTF-16 to match the UTF-16LE+BOM bytes install.ts writes —
    // schtasks /Create /XML rejects a mismatch ("unable to switch the encoding").
    expect(content).toContain('encoding="UTF-16"');
    // The action runs the hidden VBScript launcher (plan/40), not node directly,
    // so the supervisor starts with no console window.
    expect(content).toContain("wscript.exe");
    expect(content).toContain("{VBS}");
    expect(content).toContain("<Hidden>true</Hidden>");
  });

  test("vbs-launcher (Windows) template file exists on disk (plan/40)", () => {
    const p = findTemplate("vbs-launcher");
    expect(p.endsWith("task-launcher.vbs.template")).toBe(true);
    const content = readFileSync(p, "utf8");
    // Hidden window (style 0), wait=True, propagate exit code, tee to {LOG}.
    expect(content).toContain(".Run(");
    expect(content).toContain("WScript.Quit");
    expect(content).toContain("cmd /c");
    expect(content).toContain("{NODE}");
    expect(content).toContain("{SUPERVISOR}");
    expect(content).toContain("{LOG}");
  });
});

describe("renderTemplate", () => {
  const vars = {
    node: "/usr/local/bin/node",
    supervisor: "/Users/x/dist/bin/supervisord.js",
    home: "/Users/x",
    user: "jacob",
    path: "/usr/local/bin:/usr/bin:/bin",
    vbs: "/Users/x/.pi/remote/RemotePiSupervisorLauncher.vbs",
    logPath: "/Users/x/.pi/remote/supervisord.log",
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

  test("substitutes {VBS} in the task-scheduler template, action calls wscript", () => {
    const tpl = readFileSync(findTemplate("taskscheduler"), "utf8");
    const out = renderTemplate(tpl, vars);
    expect(out).not.toContain("{VBS}");
    expect(out).toContain(vars.vbs);
    // {NODE}/{SUPERVISOR} no longer appear in the XML — they moved to the VBS.
    expect(out).not.toContain("{NODE}");
    expect(out).not.toContain("{SUPERVISOR}");
  });

  test("substitutes {NODE}/{SUPERVISOR}/{LOG} in the vbs-launcher template", () => {
    const tpl = readFileSync(findTemplate("vbs-launcher"), "utf8");
    const out = renderTemplate(tpl, vars);
    expect(out).not.toContain("{NODE}");
    expect(out).not.toContain("{SUPERVISOR}");
    expect(out).not.toContain("{LOG}");
    expect(out).toContain(vars.node);
    expect(out).toContain(vars.supervisor);
    expect(out).toContain(vars.logPath);
  });
});

describe("vbsLauncherPath", () => {
  test("is absolute and ends with the launcher .vbs under ~/.pi/remote", () => {
    const p = vbsLauncherPath();
    expect(isAbsolute(p)).toBe(true);
    expect(p.endsWith("RemotePiSupervisorLauncher.vbs")).toBe(true);
    expect(p.endsWith(join(".pi", "remote", "RemotePiSupervisorLauncher.vbs"))).toBe(true);
  });
});

describe("buildCmdShim", () => {
  test("forwards all args to node with quoted node + target", () => {
    const shim = buildCmdShim("C:\\node\\node.exe", "C:\\ext\\dist\\index.js");
    expect(shim).toContain('@echo off');
    expect(shim).toContain('"C:\\node\\node.exe" "C:\\ext\\dist\\index.js" %*');
    expect(shim.endsWith("\r\n")).toBe(true);
  });
});

describe("buildElevatedCmd", () => {
  test("redirects schtasks lines to the log but leaves control-flow bare", () => {
    const out = buildElevatedCmd(
      [
        "schtasks /End /TN RemotePiSupervisor",
        "schtasks /Create /XML \"x.xml\" /TN RemotePiSupervisor /F",
        "if errorlevel 1 exit /b 1",
        "schtasks /Run /TN RemotePiSupervisor",
      ],
      "C:\\Temp\\out.log",
    );
    expect(out.startsWith("@echo off\r\n")).toBe(true);
    // schtasks lines get the redirect…
    expect(out).toContain('schtasks /End /TN RemotePiSupervisor >> "C:\\Temp\\out.log" 2>&1');
    expect(out).toContain('schtasks /Run /TN RemotePiSupervisor >> "C:\\Temp\\out.log" 2>&1');
    // …control flow does NOT (redirecting it would swallow the exit code).
    expect(out).toContain("if errorlevel 1 exit /b 1\r\n");
    expect(out).not.toContain('exit /b 1 >> ');
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

  test("matches the package.json `remote-pi` bin", () => {
    // npm only marks `bin` files executable, so the link must target the bin
    // (and the bin must run the CLI without the host packages — see
    // cli_imports.test.ts).
    const pkg = JSON.parse(readFileSync(new URL("../../package.json", import.meta.url), "utf8")) as {
      bin: Record<string, string>;
    };
    expect(pkg.bin["remote-pi"]).toBe(`dist/${basename(findRemotePiScript())}`);
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

// Windows variant (plan/40): real `.cmd` shims, not symlinks. `mutatePath:false`
// keeps the test from touching the real user PATH; `node` is injected so the
// shim contents are deterministic.
describe.skipIf(!posixOnly)("linkCliBinaries / unlinkCliBinaries (Windows .cmd shims)", () => {
  let tmpHome: string;
  let fakePaths: { remotePi: string; supervisord: string };
  const node = "C:\\Program Files\\nodejs\\node.exe";

  beforeEach(() => {
    tmpHome = mkdtempSync(join(tmpdir(), "pi-link-win-"));
    const stub = join(tmpHome, "fake-ext");
    mkdirSync(join(stub, "bin"), { recursive: true });
    fakePaths = {
      remotePi: join(stub, "index.js"),
      supervisord: join(stub, "bin", "supervisord.js"),
    };
    writeFileSync(fakePaths.remotePi, "// stub\n");
    writeFileSync(fakePaths.supervisord, "// stub\n");
  });

  afterEach(() => {
    rmSync(tmpHome, { recursive: true, force: true });
  });

  test("link writes remote-pi.cmd + pi-supervisord.cmd pointing at node + targets", () => {
    const result = linkCliBinaries(tmpHome, fakePaths, { node, mutatePath: false });
    expect(result.binDir).toBe(join(tmpHome, ".local", "bin"));
    const names = result.links.map((l) => l.name).sort();
    expect(names).toEqual(["pi-supervisord.cmd", "remote-pi.cmd"]);
    for (const link of result.links) {
      expect(existsSync(link.path)).toBe(true);
      const content = readFileSync(link.path, "utf8");
      expect(content).toContain(`"${node}"`);
      expect(content).toContain(`"${link.target}"`);
      expect(content).toContain("%*");
    }
  });

  test("link is idempotent (re-running overwrites the same .cmd files)", () => {
    linkCliBinaries(tmpHome, fakePaths, { node, mutatePath: false });
    const second = linkCliBinaries(tmpHome, fakePaths, { node, mutatePath: false });
    for (const link of second.links) {
      expect(readFileSync(link.path, "utf8")).toBe(buildCmdShim(node, link.target));
    }
  });

  test("unlink removes both .cmd shims, idempotent on second call", () => {
    linkCliBinaries(tmpHome, fakePaths, { node, mutatePath: false });
    const first = unlinkCliBinaries(tmpHome);
    expect(first.removed.map((r) => r.existed)).toEqual([true, true]);
    for (const r of first.removed) expect(existsSync(r.path)).toBe(false);
    const second = unlinkCliBinaries(tmpHome);
    expect(second.removed.map((r) => r.existed)).toEqual([false, false]);
  });
});
