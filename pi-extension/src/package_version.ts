import { readFileSync } from "node:fs";

export interface PackageIdentity {
  name: string;
  version: string;
}

/**
 * Read package identity beside the compiled source. This lets every runtime
 * entry point report the package that was actually shipped rather than a
 * manually duplicated literal.
 */
export function readPackageIdentity(): PackageIdentity {
  try {
    const packageJsonUrl = new URL("../package.json", import.meta.url);
    const parsed = JSON.parse(readFileSync(packageJsonUrl, "utf8")) as {
      name?: unknown;
      version?: unknown;
    };
    return {
      name: typeof parsed.name === "string" ? parsed.name : "remote-pi",
      version: typeof parsed.version === "string" ? parsed.version : "0.0.0",
    };
  } catch {
    return { name: "remote-pi", version: "0.0.0" };
  }
}

const PACKAGE_IDENTITY = readPackageIdentity();
export const PACKAGE_NAME = PACKAGE_IDENTITY.name;
export const PACKAGE_VERSION = PACKAGE_IDENTITY.version;
