import { readFileSync } from "node:fs";

/**
 * Read the package version beside the compiled source. This lets every runtime
 * entry point report the version that was actually shipped rather than a
 * manually duplicated literal.
 */
export function readPackageVersion(): string {
  try {
    const packageJsonUrl = new URL("../package.json", import.meta.url);
    const parsed = JSON.parse(readFileSync(packageJsonUrl, "utf8")) as { version?: unknown };
    return typeof parsed.version === "string" ? parsed.version : "0.0.0";
  } catch {
    return "0.0.0";
  }
}

export const PACKAGE_VERSION = readPackageVersion();
