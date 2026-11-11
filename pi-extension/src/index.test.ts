import { expect, test } from "vitest";

// Imported (not run directly), index.ts must hand Pi the extension factory.
test("default export is the extension factory", async () => {
  const [index, extension] = await Promise.all([import("./index.js"), import("./extension.js")]);
  expect(typeof index.default).toBe("function");
  expect(index.default).toBe(extension.default);
});
