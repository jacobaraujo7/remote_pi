import { afterEach, describe, expect, test } from "vitest";
import { homedir } from "node:os";
import { join } from "node:path";
import { remotePiHome } from "./paths.js";

const SAVED_DIR = process.env["REMOTE_PI_DIR"];
const SAVED_HOME = process.env["REMOTE_PI_HOME"];

function restore(key: string, value: string | undefined): void {
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

afterEach(() => {
  restore("REMOTE_PI_DIR", SAVED_DIR);
  restore("REMOTE_PI_HOME", SAVED_HOME);
});

describe("remotePiHome precedence", () => {
  test("defaults to ~/.pi/remote when nothing is set", () => {
    delete process.env["REMOTE_PI_DIR"];
    delete process.env["REMOTE_PI_HOME"];
    expect(remotePiHome()).toBe(join(homedir(), ".pi", "remote"));
  });

  test("REMOTE_PI_HOME is treated as a stand-in $HOME (appends .pi/remote)", () => {
    delete process.env["REMOTE_PI_DIR"];
    process.env["REMOTE_PI_HOME"] = "/tmp/fake-home";
    expect(remotePiHome()).toBe(join("/tmp/fake-home", ".pi", "remote"));
  });

  test("REMOTE_PI_DIR is an absolute override with no .pi/remote suffix", () => {
    process.env["REMOTE_PI_DIR"] = "/Users/x/.config/pi/remote-pi";
    process.env["REMOTE_PI_HOME"] = "/tmp/fake-home"; // ignored when DIR is set
    expect(remotePiHome()).toBe("/Users/x/.config/pi/remote-pi");
  });

  test("an empty REMOTE_PI_DIR falls through to REMOTE_PI_HOME", () => {
    process.env["REMOTE_PI_DIR"] = "";
    process.env["REMOTE_PI_HOME"] = "/tmp/fake-home";
    expect(remotePiHome()).toBe(join("/tmp/fake-home", ".pi", "remote"));
  });

  test("resolved at call time (a later env change is picked up)", () => {
    process.env["REMOTE_PI_DIR"] = "/first";
    expect(remotePiHome()).toBe("/first");
    process.env["REMOTE_PI_DIR"] = "/second";
    expect(remotePiHome()).toBe("/second");
  });
});
