import { describe, it, expect } from "vitest"
import { readFileSync, existsSync } from "fs"
import { join, dirname } from "path"
import { fileURLToPath } from "url"

// Regression guard for issues #22/#23: v1.2.4 shipped without
// lib.protocol.ts in npm `files`, so `index.ts` threw
// "Cannot find module './lib.protocol'" and the whole plugin failed to load.
// This test fails if any runtime relative import is not covered by `files`,
// or if a bare specifier used at runtime is missing from dependencies.

const root = join(dirname(fileURLToPath(import.meta.url)))
const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf-8")) as {
  files: string[]
  dependencies: Record<string, string>
}

// Runtime entry points shipped to npm (test files are never published).
const RUNTIME_SOURCES = ["index.ts", "lib.ts", "lib.protocol.ts", "lib.vault.ts", "db.ts"]

function relativeImports(source: string): string[] {
  const text = readFileSync(join(root, source), "utf-8")
  const found = new Set<string>()
  for (const re of [/from\s+["'](\.[^"']+)["']/g, /import\(\s*["'](\.[^"']+)["']\s*\)/g]) {
    for (const m of text.matchAll(re)) found.add(m[1])
  }
  return [...found]
}

/** "./lib.protocol.js" -> "lib.protocol.ts", "./db" -> "db.ts", ... */
function resolvesToPublishedFile(spec: string): string | null {
  const base = spec.replace(/^\.\//, "").replace(/\.js$/, "")
  for (const candidate of [`${base}.ts`, `${base}.tsx`, base]) {
    if ((pkg.files as string[]).includes(candidate) && existsSync(join(root, candidate)))
      return candidate
  }
  return null
}

describe("packaging (issues #22/#23)", () => {
  it("lib.protocol.ts is published", () => {
    expect(pkg.files).toContain("lib.protocol.ts")
  })

  it("every runtime relative import resolves to a published file", () => {
    const missing: string[] = []
    for (const source of RUNTIME_SOURCES) {
      for (const spec of relativeImports(source)) {
        if (!resolvesToPublishedFile(spec)) missing.push(`${source} -> ${spec}`)
      }
    }
    expect(missing).toEqual([])
  })

  it("bare runtime imports are declared dependencies (effect)", () => {
    // index.ts and tui.tsx import "effect"; it used to resolve only
    // transitively via @opencode-ai/plugin, which npm does not guarantee.
    expect(pkg.dependencies["effect"]).toBeDefined()
  })
})
