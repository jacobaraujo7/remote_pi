#!/usr/bin/env node
// Fails the build if pt-BR.json / es.json drift from en.json's key tree.
// en.json is the source of truth (same rule as `slang` in cockpit/): every
// locale must translate exactly the same keys, no more, no less.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const dir = path.dirname(fileURLToPath(import.meta.url));
const messagesDir = path.join(dir, "..", "src", "messages");

function loadJson(locale) {
  const raw = readFileSync(path.join(messagesDir, `${locale}.json`), "utf8");
  return JSON.parse(raw);
}

function flatten(obj, prefix = "") {
  const keys = new Set();
  for (const [key, value] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (value && typeof value === "object" && !Array.isArray(value)) {
      for (const k of flatten(value, path)) keys.add(k);
    } else {
      keys.add(path);
    }
  }
  return keys;
}

const SOURCE_LOCALE = "en";
const TARGET_LOCALES = ["pt-BR", "es"];

const sourceKeys = flatten(loadJson(SOURCE_LOCALE));
let ok = true;

for (const locale of TARGET_LOCALES) {
  const targetKeys = flatten(loadJson(locale));
  const missing = [...sourceKeys].filter((k) => !targetKeys.has(k)).sort();
  const extra = [...targetKeys].filter((k) => !sourceKeys.has(k)).sort();

  if (missing.length > 0 || extra.length > 0) {
    ok = false;
    console.error(`\n[check-messages] ${locale}.json is out of sync with en.json:`);
    if (missing.length > 0) {
      console.error(`  Missing keys (${missing.length}):`);
      for (const k of missing) console.error(`    - ${k}`);
    }
    if (extra.length > 0) {
      console.error(`  Extra keys (${extra.length}):`);
      for (const k of extra) console.error(`    + ${k}`);
    }
  }
}

if (!ok) {
  console.error("\n[check-messages] Fix the key trees above before building.\n");
  process.exit(1);
}

console.log(`[check-messages] en/pt-BR/es key trees match (${sourceKeys.size} keys each).`);
