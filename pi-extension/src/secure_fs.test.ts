import { describe, expect, test } from "vitest";
import { existsSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import {
  PRIVATE_DIR_MODE,
  PRIVATE_FILE_MODE,
  ensurePrivateDirSync,
  writePrivateFileAtomic,
  writePrivateFileAtomicSync,
  writePrivateFileSync,
} from "./secure_fs.js";

function mode(path: string): number {
  return statSync(path).mode & 0o777;
}

const checkModes = process.platform !== "win32";

describe("secure_fs", () => {
  test("ensurePrivateDirSync creates and tightens directories to 0700 on POSIX", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-secure-dir-"));
    const target = join(dir, "nested");
    ensurePrivateDirSync(target);
    expect(existsSync(target)).toBe(true);
    if (checkModes) expect(mode(target)).toBe(PRIVATE_DIR_MODE);
  });

  test("writePrivateFileSync creates parent 0700 and file 0600 on POSIX", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-secure-file-"));
    const path = join(dir, "remote", "identity.json");
    writePrivateFileSync(path, "secret");
    expect(readFileSync(path, "utf8")).toBe("secret");
    if (checkModes) {
      expect(mode(dirname(path))).toBe(PRIVATE_DIR_MODE);
      expect(mode(path)).toBe(PRIVATE_FILE_MODE);
    }
  });

  test("writePrivateFileAtomic replaces file contents and preserves 0600 on POSIX", async () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-secure-atomic-"));
    const path = join(dir, "peers.json");
    writeFileSync(path, "old", { mode: 0o644 });
    await writePrivateFileAtomic(path, "new");
    expect(readFileSync(path, "utf8")).toBe("new");
    if (checkModes) expect(mode(path)).toBe(PRIVATE_FILE_MODE);
  });

  test("writePrivateFileAtomicSync writes in the same directory and leaves no temp files", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-secure-atomic-sync-"));
    const path = join(dir, "daemons.json");
    writePrivateFileAtomicSync(path, "{}\n");
    expect(readFileSync(path, "utf8")).toBe("{}\n");
    if (checkModes) expect(mode(path)).toBe(PRIVATE_FILE_MODE);
  });
});
