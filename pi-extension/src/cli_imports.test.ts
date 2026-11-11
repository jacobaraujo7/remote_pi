import { describe, expect, test } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

// Everything that runs under plain `node` must start without the host packages:
// they are peerDependencies, and Pi-managed installs (`--legacy-peer-deps`)
// omit them. Walk each entry's runtime import graph (type-only imports are
// elided by the transpile, exactly as tsc does) and fail on any host package.

const srcDir = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(readFileSync(resolve(srcDir, "../package.json"), "utf8")) as {
  bin: Record<string, string>;
  peerDependencies: Record<string, string>;
};
const hostPackages = Object.keys(pkg.peerDependencies);
const extensionModule = resolve(srcDir, "extension.ts");

function isHostSpecifier(spec: string): boolean {
  return hostPackages.some((name) => spec === name || spec.startsWith(`${name}/`));
}

/** `dist/foo/bar.js` → `src/foo/bar.ts` */
function sourceOf(distPath: string): string {
  return resolve(srcDir, distPath.replace(/^dist\//, "").replace(/\.js$/, ".ts"));
}

function transpile(file: string): string {
  return ts.transpileModule(readFileSync(file, "utf8"), {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
}

function runtimeSpecifiers(file: string): string[] {
  return ts.preProcessFile(transpile(file), true, true).importedFiles.map((f) => f.fileName);
}

/** Module specifiers of the runtime `import … from` / `export … from` declarations. */
function staticSpecifiers(file: string): string[] {
  const sf = ts.createSourceFile(file, transpile(file), ts.ScriptTarget.ES2022);
  return sf.statements.flatMap((st) =>
    (ts.isImportDeclaration(st) || ts.isExportDeclaration(st)) &&
    st.moduleSpecifier !== undefined &&
    ts.isStringLiteral(st.moduleSpecifier)
      ? [st.moduleSpecifier.text]
      : [],
  );
}

/**
 * Bare specifiers → the local files that import them, for every module
 * reachable from `entry` (static and dynamic imports). `skip` files are not
 * entered.
 */
function runtimeGraph(entry: string, skip: ReadonlySet<string> = new Set()): Map<string, string[]> {
  const external = new Map<string, string[]>();
  const seen = new Set<string>(skip);
  const queue = [entry];
  while (queue.length > 0) {
    const file = queue.pop()!;
    if (seen.has(file)) continue;
    seen.add(file);
    for (const spec of runtimeSpecifiers(file)) {
      if (spec.startsWith(".")) {
        const target = resolve(dirname(file), spec.replace(/\.js$/, ".ts"));
        if (!existsSync(target)) throw new Error(`${file}: cannot resolve ${spec}`);
        queue.push(target);
      } else {
        external.set(spec, [...(external.get(spec) ?? []), file]);
      }
    }
  }
  return external;
}

function hostImports(graph: Map<string, string[]>): string[] {
  return [...graph]
    .filter(([spec]) => isHostSpecifier(spec))
    .map(([spec, files]) => `${spec} ← ${files.map((f) => f.slice(srcDir.length + 1)).join(", ")}`);
}

// Plain-node entries: every package bin, plus the mesh MCP server that
// `remote-pi claude` spawns with `node`.
const nodeEntries = [...Object.values(pkg.bin), "dist/mcp/mesh_server.js"];
const indexModule = resolve(srcDir, "index.ts");

describe("host-independent entry points", () => {
  test("peerDependencies list the host packages", () => {
    expect(hostPackages).toEqual(
      expect.arrayContaining(["@earendil-works/pi-coding-agent", "@earendil-works/pi-tui", "typebox"]),
    );
  });

  test("dist/index.js is a bin", () => {
    expect(nodeEntries).toContain("dist/index.js");
  });

  // index.ts imports the extension lazily, only when Pi loads it (checked
  // below), so its CLI graph stops there.
  test.each(nodeEntries)("%s never loads a host package at runtime", (entry) => {
    const source = sourceOf(entry);
    const skip = new Set(source === indexModule ? [extensionModule] : []);
    expect(hostImports(runtimeGraph(source, skip))).toEqual([]);
  });

  test("index.ts imports the extension only dynamically", () => {
    // A static import would load the extension (and the host) before the
    // direct-run check, breaking the `remote-pi` bin without peers.
    expect(staticSpecifiers(indexModule)).not.toContain("./extension.js");
    expect(runtimeSpecifiers(indexModule)).toContain("./extension.js");
  });

  test("the walker does see the extension's host imports (control)", () => {
    const specs = [...runtimeGraph(extensionModule).keys()];
    expect(specs.filter(isHostSpecifier)).toEqual(
      expect.arrayContaining(["@earendil-works/pi-coding-agent", "@earendil-works/pi-tui", "typebox"]),
    );
  });
});
