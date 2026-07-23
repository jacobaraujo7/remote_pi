import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  MeshClient,
  MeshFetchInvalidResponseError,
  MeshFetchUnavailableError,
} from "./client.js";

const VALID_BLOB = new TextEncoder().encode('{"members":[]}');
const VALID_SIGNATURE = Uint8Array.from({ length: 64 }, (_, index) => index);

function response(
  status: number,
  payload: unknown = undefined,
): Response {
  return {
    status,
    json: vi.fn().mockResolvedValue(payload),
  } as unknown as Response;
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("MeshClient", () => {
  test("returns a strictly decoded envelope for a valid 200 response", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      response(200, {
        blob: Buffer.from(VALID_BLOB).toString("base64"),
        sig: Buffer.from(VALID_SIGNATURE).toString("base64url"),
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await new MeshClient("https://relay.test/").get("abc", 7);

    expect(result).toEqual({
      blob: VALID_BLOB,
      sig: VALID_SIGNATURE,
    });
    expect(fetchMock).toHaveBeenCalledWith(
      "https://relay.test/mesh/abc?since=7",
      expect.objectContaining({
        method: "GET",
        signal: expect.any(AbortSignal),
      }),
    );
    expect(vi.getTimerCount()).toBe(0);
  });

  test.each([304, 404])("maps status %i to null", async (status) => {
    const res = response(status);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(res));

    await expect(new MeshClient("https://relay.test").get("abc")).resolves.toBeNull();
    expect(res.json).not.toHaveBeenCalled();
    expect(vi.getTimerCount()).toBe(0);
  });

  test("classifies a network failure as unavailable", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network failed")));

    await expect(new MeshClient("https://relay.test").get("abc"))
      .rejects.toBeInstanceOf(MeshFetchUnavailableError);
    expect(vi.getTimerCount()).toBe(0);
  });

  test.each([
    [503, MeshFetchUnavailableError],
    [400, MeshFetchInvalidResponseError],
    [200, MeshFetchInvalidResponseError, { blob: "e30=" }],
  ])("classifies representative unavailable and invalid responses", async (status, expectedError, payload) => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response(status, payload)));

    await expect(new MeshClient("https://relay.test").get("abc"))
      .rejects.toBeInstanceOf(expectedError);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("classifies JSON body parsing failure as invalid", async () => {
    const secretBody = "invalid JSON";
    const res = {
      status: 200,
      json: vi.fn().mockRejectedValue(new SyntaxError(secretBody)),
    } as unknown as Response;
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(res));

    const error = await new MeshClient("https://relay.test")
      .get("abc")
      .catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(MeshFetchInvalidResponseError);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("classifies response-body transport failure as unavailable", async () => {
    const secretCause = "body stream failed";
    const res = {
      status: 200,
      json: vi.fn().mockRejectedValue(new TypeError(secretCause)),
    } as unknown as Response;
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(res));

    const error = await new MeshClient("https://relay.test")
      .get("abc")
      .catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(MeshFetchUnavailableError);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("aborts a never-resolving fetch at the injected deadline", async () => {
    const fetchMock = vi.fn(
      (_url: string | URL | Request, init?: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener(
            "abort",
            () => reject(new DOMException("aborted", "AbortError")),
            { once: true },
          );
        }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const outcome = new MeshClient("https://relay.test", {
      requestTimeoutMs: 25,
    })
      .get("abc")
      .catch((caught: unknown) => caught);

    await vi.advanceTimersByTimeAsync(25);

    expect(await outcome).toBeInstanceOf(MeshFetchUnavailableError);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("uses the same deadline to abort a never-resolving body read", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        status: 200,
        json: vi.fn(() => new Promise<never>(() => {})),
      } as unknown as Response),
    );
    const outcome = new MeshClient("https://relay.test", {
      requestTimeoutMs: 25,
    })
      .get("abc")
      .catch((caught: unknown) => caught);

    await vi.advanceTimersByTimeAsync(25);

    expect(await outcome).toBeInstanceOf(MeshFetchUnavailableError);
    expect(vi.getTimerCount()).toBe(0);
  });


});
