import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  addDaemon,
  listDaemons,
  loadRegistry,
  migrateRegistryNames,
  normalizeCwd,
  registryPath,
  removeDaemon,
  saveRegistry,
} from "./registry.js";
import { daemonIdForCwd } from "./id.js";
import { defaultAgentName } from "../session/local_config.js";

/** Each test runs against an isolated $HOME-like directory so the registry
 *  writes never touch the developer's real `~/.pi/remote/daemons.json`. */
let testHome: string;

beforeEach(() => {
  testHome = mkdtempSync(join(tmpdir(), "pi-regtest-"));
  process.env["REMOTE_PI_HOME"] = testHome;
});

afterEach(() => {
  delete process.env["REMOTE_PI_HOME"];
  try { rmSync(testHome, { recursive: true, force: true }); } catch { /* best-effort */ }
});

describe("registryPath", () => {
  test("honors REMOTE_PI_HOME env override", () => {
    expect(registryPath()).toBe(join(testHome, ".pi", "remote", "daemons.json"));
  });
});

describe("normalizeCwd", () => {
  test("expands ~/ relative to HOME", () => {
    // We can't easily test ~ expansion against the real homedir without
    // creating an actual subdir there. Instead, simulate by creating a
    // tmp folder and asking normalizeCwd to canonicalize it absolutely.
    const tmp = mkdtempSync(join(tmpdir(), "pi-norm-"));
    expect(normalizeCwd(tmp)).toBe(realpathSync(tmp));
  });

  test("resolves relative paths against process.cwd()", () => {
    // `.` resolves to the test runner's cwd (project root). Just verify
    // it's absolute and canonicalized.
    const got = normalizeCwd(".");
    expect(got.startsWith("/")).toBe(true);
    expect(got).toBe(realpathSync("."));
  });

  test("throws on empty input", () => {
    expect(() => normalizeCwd("")).toThrow(/required/i);
    expect(() => normalizeCwd("   ")).toThrow(/required/i);
  });

  test("throws on non-existent path (realpath ENOENT)", () => {
    expect(() => normalizeCwd("/no/such/path/anywhere/xyz-pi-test")).toThrow();
  });

  test("symlinks resolve to canonical realpath", () => {
    const tmp = mkdtempSync(join(tmpdir(), "pi-symlink-"));
    const real = join(tmp, "real");
    mkdirSync(real);
    const link = join(tmp, "link");
    symlinkSync(real, link);
    expect(normalizeCwd(link)).toBe(normalizeCwd(real));
  });
});

describe("loadRegistry / saveRegistry", () => {
  test("empty when file absent", () => {
    const reg = loadRegistry();
    expect(reg).toEqual({ daemons: [] });
  });

  test("round-trip: save then load", () => {
    saveRegistry({ daemons: [{ cwd: "/tmp/a" }, { cwd: "/tmp/b" }] });
    expect(loadRegistry()).toEqual({ daemons: [{ cwd: "/tmp/a" }, { cwd: "/tmp/b" }] });
  });

  test("creates parent dirs on save", () => {
    saveRegistry({ daemons: [] });
    expect(existsSync(registryPath())).toBe(true);
  });

  test("malformed JSON tolerated (returns empty)", () => {
    const path = registryPath();
    mkdirSync(join(testHome, ".pi", "remote"), { recursive: true });
    require("node:fs").writeFileSync(path, "{not-json");
    expect(loadRegistry()).toEqual({ daemons: [] });
  });

  test("unknown shape tolerated", () => {
    const path = registryPath();
    mkdirSync(join(testHome, ".pi", "remote"), { recursive: true });
    require("node:fs").writeFileSync(path, JSON.stringify({ foo: "bar" }));
    expect(loadRegistry()).toEqual({ daemons: [] });
  });
});

describe("addDaemon", () => {
  test("registers a fresh cwd and returns derived id", () => {
    const tmp = mkdtempSync(join(tmpdir(), "pi-add-"));
    const result = addDaemon(tmp);
    expect(result.id).toBe(daemonIdForCwd(realpathSync(tmp)));
    expect(result.cwd).toBe(realpathSync(tmp));
    expect(listDaemons().map((d) => d.cwd)).toEqual([realpathSync(tmp)]);
  });

  test("rejects duplicate cwd (same normalized path)", () => {
    const tmp = mkdtempSync(join(tmpdir(), "pi-dup-"));
    addDaemon(tmp);
    expect(() => addDaemon(tmp)).toThrow(/already registered/i);
  });

  test("relative path canonicalizes to same entry as absolute", () => {
    const tmp = mkdtempSync(join(tmpdir(), "pi-relabs-"));
    addDaemon(tmp);
    // Trying to add via a symlink → same normalized path → duplicate.
    const link = join(tmpdir(), `pi-relabs-link-${Date.now()}`);
    symlinkSync(tmp, link);
    expect(() => addDaemon(link)).toThrow(/already registered/i);
  });

  test("on-disk file matches loadRegistry output", () => {
    const tmp = mkdtempSync(join(tmpdir(), "pi-disk-"));
    addDaemon(tmp);
    const onDisk = JSON.parse(readFileSync(registryPath(), "utf8")) as { daemons: Array<{cwd: string}> };
    expect(onDisk.daemons).toHaveLength(1);
    expect(onDisk.daemons[0]!.cwd).toBe(realpathSync(tmp));
  });
});

describe("removeDaemon", () => {
  test("removes by id and returns the cwd", () => {
    const tmp = mkdtempSync(join(tmpdir(), "pi-rm-"));
    const { id } = addDaemon(tmp);
    const result = removeDaemon(id);
    expect(result.removed).toBe(true);
    expect(result.cwd).toBe(realpathSync(tmp));
    expect(listDaemons()).toEqual([]);
  });

  test("unknown id is a no-op (removed=false)", () => {
    const result = removeDaemon("ffffffff");
    expect(result.removed).toBe(false);
    expect(result.cwd).toBeUndefined();
  });

  test("only removes the matching entry — others stay", () => {
    const a = mkdtempSync(join(tmpdir(), "pi-multi-a-"));
    const b = mkdtempSync(join(tmpdir(), "pi-multi-b-"));
    const { id: idA } = addDaemon(a);
    addDaemon(b);
    removeDaemon(idA);
    const remaining = listDaemons();
    expect(remaining).toHaveLength(1);
    expect(remaining[0]!.cwd).toBe(realpathSync(b));
  });
});

describe("listDaemons", () => {
  test("returns derived ids alongside cwds, in insertion order", () => {
    const a = mkdtempSync(join(tmpdir(), "pi-list-a-"));
    const b = mkdtempSync(join(tmpdir(), "pi-list-b-"));
    addDaemon(a);
    addDaemon(b);
    const out = listDaemons();
    expect(out).toEqual([
      { id: daemonIdForCwd(realpathSync(a)), cwd: realpathSync(a), name: defaultAgentName(realpathSync(a)) },
      { id: daemonIdForCwd(realpathSync(b)), cwd: realpathSync(b), name: defaultAgentName(realpathSync(b)) },
    ]);
  });

  test("legacy entry without a name falls back to the folder-derived name", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-legacy-"));
    const cwd = realpathSync(dir);
    saveRegistry({ daemons: [{ cwd }] }); // pre-name-field shape
    const out = listDaemons();
    expect(out).toEqual([{ id: daemonIdForCwd(cwd), cwd, name: defaultAgentName(cwd) }]);
  });

  test("empty registry yields []", () => {
    expect(listDaemons()).toEqual([]);
  });
});

describe("migrateRegistryNames", () => {
  test("backfills folder names into legacy entries and persists", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-mig-"));
    const cwd = realpathSync(dir);
    saveRegistry({ daemons: [{ cwd }] }); // legacy: no name

    const changed = migrateRegistryNames();
    expect(changed).toBe(1);

    const onDisk = JSON.parse(readFileSync(registryPath(), "utf8")) as {
      daemons: Array<{ cwd: string; name?: string }>;
    };
    expect(onDisk.daemons[0]!.name).toBe(defaultAgentName(cwd));
  });

  test("is idempotent — a second run changes nothing", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-mig2-"));
    addDaemon(dir); // already has a name
    expect(migrateRegistryNames()).toBe(0);
  });
});
