import type { PeerInfo } from "./broker.js";

/** Shared wire limits measured in JavaScript UTF-16 code units (`.length`). */
export const MAX_PEERS_UPDATE_ENTRIES = 1024;
export const MAX_CWD_LENGTH = 4096;
export const MAX_NAME_LENGTH = 256;
export const MAX_ADDRESS_LENGTH = 4352;

export function isBoundedPeerInfo(value: unknown): value is PeerInfo {
  if (!value || typeof value !== "object") return false;
  const { cwd, name, address } = value as PeerInfo;
  return typeof cwd === "string" && cwd.length <= MAX_CWD_LENGTH &&
    typeof name === "string" && name.length <= MAX_NAME_LENGTH &&
    typeof address === "string" && address.length <= MAX_ADDRESS_LENGTH;
}

export function isBoundedPeerRoster(
  infos: readonly PeerInfo[],
): boolean {
  return infos.length <= MAX_PEERS_UPDATE_ENTRIES && infos.every(isBoundedPeerInfo);
}

export function isBoundedPeerAddresses(addresses: readonly unknown[]): boolean {
  return addresses.length <= MAX_PEERS_UPDATE_ENTRIES &&
    addresses.every((address) =>
      typeof address === "string" && address.length <= MAX_ADDRESS_LENGTH
    );
}
