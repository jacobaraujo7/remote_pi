import { afterEach, describe, expect, test } from "vitest";
import { homedir } from "node:os";
import { join } from "node:path";
import { remotePiConfigHome, remotePiHome } from "./paths.js";

const SAVED_DIR = process.env["REMOTE_PI_DIR"];
const SAVED_HOME = process.env["REMOTE_PI_HOME"];
const SAVED_AGENT_DIR = process.env["PI_CODING_AGENT_DIR"];

function restore(key: string, value: string | undefined): void {
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

afterEach(() => {
  restore("REMOTE_PI_DIR", SAVED_DIR);
  restore("REMOTE_PI_HOME", SAVED_HOME);
  restore("PI_CODING_AGENT_DIR", SAVED_AGENT_DIR);
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

describe("remotePiConfigHome precedence", () => {
  test("PI_CODING_AGENT_DIR unset → falls back to remotePiHome()", () => {
    delete process.env["PI_CODING_AGENT_DIR"];
    delete process.env["REMOTE_PI_DIR"];
    delete process.env["REMOTE_PI_HOME"];
    expect(remotePiConfigHome()).toBe(join(homedir(), ".pi", "remote"));
    expect(remotePiConfigHome()).toBe(remotePiHome());
  });

  test("PI_CODING_AGENT_DIR set → <agentDir>/remote (default ~/.pi keeps historical path)", () => {
    process.env["PI_CODING_AGENT_DIR"] = join(homedir(), ".pi");
    expect(remotePiConfigHome()).toBe(join(homedir(), ".pi", "remote"));
  });

  test("PI_CODING_AGENT_DIR wins over the state resolver (REMOTE_PI_DIR)", () => {
    process.env["PI_CODING_AGENT_DIR"] = "/agent/home";
    process.env["REMOTE_PI_DIR"] = "/state/root"; // steers state, not config
    expect(remotePiConfigHome()).toBe(join("/agent", "home", "remote"));
    expect(remotePiHome()).toBe("/state/root");
  });

  test("an empty PI_CODING_AGENT_DIR falls through to remotePiHome()", () => {
    process.env["PI_CODING_AGENT_DIR"] = "";
    process.env["REMOTE_PI_DIR"] = "/state/root";
    expect(remotePiConfigHome()).toBe("/state/root");
  });

  test("resolved at call time (a later env change is picked up)", () => {
    process.env["PI_CODING_AGENT_DIR"] = "/first";
    expect(remotePiConfigHome()).toBe(join("/first", "remote"));
    process.env["PI_CODING_AGENT_DIR"] = "/second";
    expect(remotePiConfigHome()).toBe(join("/second", "remote"));
  });
});
