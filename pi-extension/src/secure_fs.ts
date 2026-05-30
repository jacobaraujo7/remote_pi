import {
  appendFileSync,
  chmodSync,
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { appendFile, chmod, mkdir, open, rename, unlink, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { randomBytes } from "node:crypto";

export const PRIVATE_DIR_MODE = 0o700;
export const PRIVATE_FILE_MODE = 0o600;

function isPosix(): boolean {
  return process.platform !== "win32";
}

function tmpPathFor(path: string): string {
  return join(dirname(path), `.${process.pid}.${Date.now()}.${randomBytes(6).toString("hex")}.tmp`);
}

export async function ensurePrivateDir(path: string): Promise<void> {
  await mkdir(path, { recursive: true, mode: PRIVATE_DIR_MODE });
  if (!isPosix()) return;
  try { await chmod(path, PRIVATE_DIR_MODE); } catch { /* best-effort on non-POSIX mounts */ }
}

export function ensurePrivateDirSync(path: string): void {
  mkdirSync(path, { recursive: true, mode: PRIVATE_DIR_MODE });
  if (!isPosix()) return;
  try { chmodSync(path, PRIVATE_DIR_MODE); } catch { /* best-effort on non-POSIX mounts */ }
}

export async function ensurePrivateParent(path: string): Promise<void> {
  await ensurePrivateDir(dirname(path));
}

export function ensurePrivateParentSync(path: string): void {
  ensurePrivateDirSync(dirname(path));
}

export async function writePrivateFile(path: string, data: string | Buffer): Promise<void> {
  await ensurePrivateParent(path);
  await writeFile(path, data, { mode: PRIVATE_FILE_MODE });
  if (!isPosix()) return;
  try { await chmod(path, PRIVATE_FILE_MODE); } catch { /* best-effort */ }
}

export function writePrivateFileSync(path: string, data: string | Buffer): void {
  ensurePrivateParentSync(path);
  writeFileSync(path, data, { mode: PRIVATE_FILE_MODE });
  if (!isPosix()) return;
  try { chmodSync(path, PRIVATE_FILE_MODE); } catch { /* best-effort */ }
}

export async function writePrivateFileAtomic(path: string, data: string | Buffer): Promise<void> {
  await ensurePrivateParent(path);
  const tmp = tmpPathFor(path);
  try {
    await writeFile(tmp, data, { mode: PRIVATE_FILE_MODE });
    if (isPosix()) {
      try { await chmod(tmp, PRIVATE_FILE_MODE); } catch { /* best-effort */ }
    }
    const handle = await open(tmp, "r");
    try { await handle.sync(); } finally { await handle.close(); }
    await rename(tmp, path);
    if (isPosix()) {
      try { await chmod(path, PRIVATE_FILE_MODE); } catch { /* best-effort */ }
    }
  } catch (err) {
    try { await unlink(tmp); } catch { /* best-effort cleanup */ }
    throw err;
  }
}

export function writePrivateFileAtomicSync(path: string, data: string | Buffer): void {
  ensurePrivateParentSync(path);
  const tmp = tmpPathFor(path);
  try {
    writeFileSync(tmp, data, { mode: PRIVATE_FILE_MODE });
    if (isPosix()) {
      try { chmodSync(tmp, PRIVATE_FILE_MODE); } catch { /* best-effort */ }
    }
    const fd = openSync(tmp, "r");
    try { fsyncSync(fd); } finally { closeSync(fd); }
    renameSync(tmp, path);
    if (isPosix()) {
      try { chmodSync(path, PRIVATE_FILE_MODE); } catch { /* best-effort */ }
    }
  } catch (err) {
    try { unlinkSync(tmp); } catch { /* best-effort cleanup */ }
    throw err;
  }
}

export async function appendPrivateFile(path: string, data: string | Buffer): Promise<void> {
  await ensurePrivateParent(path);
  await appendFile(path, data, { mode: PRIVATE_FILE_MODE });
  if (!isPosix()) return;
  try { await chmod(path, PRIVATE_FILE_MODE); } catch { /* best-effort */ }
}

export function appendPrivateFileSync(path: string, data: string | Buffer): void {
  ensurePrivateParentSync(path);
  appendFileSync(path, data, { mode: PRIVATE_FILE_MODE });
  if (!isPosix()) return;
  try { chmodSync(path, PRIVATE_FILE_MODE); } catch { /* best-effort */ }
}

export function chmodPrivatePathSync(path: string, mode: number): void {
  if (!isPosix() || !existsSync(path)) return;
  try { chmodSync(path, mode); } catch { /* best-effort */ }
}
