/**
 * Plan/25 Wave D — pure formatter for the `/remote-pi peers` output.
 *
 * Lives in its own module so it can be unit-tested without booting the full
 * extension (no keychain access, no relay client, no mocks needed). The
 * extension imports the function and wraps it with the `_sessionPeer`
 * `list_peers` request.
 *
 * Input shape: the broker's `list_peers_reply` body returns peer names as
 * plain strings — local peers without a prefix (`sess-1`, `agent-2`),
 * cross-PC peers with a `<pc_label>:<peer>` prefix (`casa:sess-3`).
 */

// Windows local peer ids embed a drive-letter colon (e.g. "C:\Users\...@Name"),
// which collides with the "<pc_label>:<rest>" remote-peer convention (both put
// a colon early in the string). A drive letter is always a single ASCII letter
// immediately followed by a path separator, so that specific shape is never a
// real pc_label — treat it as local rather than mis-splitting on it. Without
// this guard, every local peer on Windows renders as a bogus remote peer
// under a one-letter pc label (e.g. "C:\Users\ich\...@Trading-Bot" becomes
// remote label "C", peer name "\Users\ich\...@Trading-Bot").
const WINDOWS_DRIVE_LETTER_RE = /^[A-Za-z]:[\\/]/;

export function formatPeerInventory(peers: string[], selfName?: string): string {
  const locals: string[] = [];
  const remotes = new Map<string, string[]>();
  for (const p of peers) {
    if (selfName && p === selfName) continue;
    const idx = p.indexOf(":");
    if (idx > 0 && idx < p.length - 1 && !WINDOWS_DRIVE_LETTER_RE.test(p)) {
      const label = p.slice(0, idx);
      const name = p.slice(idx + 1);
      const bucket = remotes.get(label) ?? [];
      bucket.push(name);
      remotes.set(label, bucket);
    } else {
      locals.push(p);
    }
  }
  const lines: string[] = ["  local:"];
  if (locals.length === 0) {
    lines.push("    (none)");
  } else {
    for (const n of locals.sort()) lines.push(`    ${n}`);
  }
  const sortedLabels = [...remotes.keys()].sort();
  for (const label of sortedLabels) {
    lines.push("");
    lines.push(`  remote:${label}`);
    for (const n of (remotes.get(label) ?? []).sort()) lines.push(`    ${n}`);
  }
  return lines.join("\n");
}
