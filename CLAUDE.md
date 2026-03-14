# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Demark** is a Swift package that converts HTML to Markdown, supporting iOS 16+, macOS 14+, watchOS 10+, tvOS 17+, and visionOS 1+. It requires Swift 6.0+ and has zero external dependencies (uses only WebKit and Foundation).

## Commands

### Build & Test
```bash
swift build -v
swift test -v
```

### Linting & Formatting
```bash
./scripts/lint.sh          # Run all checks (SwiftLint + SwiftFormat)
./scripts/swiftformat.sh   # Check/fix formatting
./scripts/swiftlint.sh     # Check/fix lint issues
```

### Example App
```bash
./run-example.sh           # Quick run
cd Example && swift run DemarkExample
cd Example && swift build -v
```

## Architecture

Demark uses a **dual-engine architecture** to balance accuracy vs. performance:

### Engines

| Engine | Implementation | Performance | Thread Safety | Use Case |
|--------|---------------|-------------|---------------|----------|
| **Turndown** (default) | WKWebView + JS | ~100ms first, ~10-50ms subsequent | `@MainActor` only | Complex/malformed HTML, full option support |
| **html-to-md** | JavaScriptCore | ~5-10ms | Background-thread safe | High throughput, simple HTML |

### Core Components

- **`Demark.swift`** — Public `Demark` class (`@MainActor`) and internal `ConversionRuntime`. Single entry point: `convertToMarkdown(_ html:, options:) async throws -> String`. Implements fallback: Turndown first, then html-to-md on failure.
- **`DemarkTypes.swift`** — `DemarkOptions`, `DemarkError`, and supporting enums (`ConversionEngine`, `DemarkHeadingStyle`, `DemarkCodeBlockStyle`).
- **`TurndownRuntime.swift`** — WKWebView-based engine; must run on Main Thread. Loads `turndown.min.js` and evaluates JavaScript for real DOM parsing.
- **`HTMLToMdRuntime.swift`** — JavaScriptCore-based engine using a serial `DispatchQueue` with `@unchecked Sendable`; loads `html-to-md.min.js`.
- **`BundleResourceHelper.swift`** — Locates JS library resources across `Bundle.module`, `Bundle.main`, and class-specific bundle paths.
- **`Sources/Demark/Resources/`** — Vendored JS libraries (`turndown.min.js`, `html-to-md.min.js`).

### Data Flow
```
HTML input → Demark.convertToMarkdown() → ConversionRuntime
  → validate input
  → route to engine (Turndown or html-to-md per options)
  → fallback to other engine on failure
  → normalize markdown (bullet markers, whitespace)
  → Markdown string output
```

### Thread Safety
- `Demark` and `TurndownRuntime` are `@MainActor` isolated — always call from the main actor.
- `HTMLToMdRuntime` uses a serial dispatch queue and is background-thread safe.

## Code Style

- **Line length**: 120 chars warning, 150 chars error
- **Indentation**: 4 spaces, max width 120
- **Trailing commas**: always
- **Import grouping**: testable-bottom
- **File headers**: required (template enforced by SwiftLint)
- **Swift language mode**: 6 (strict concurrency)
- Tests use **swift-testing** framework (not XCTest) — use `#expect()` and `@Test` macros.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs three parallel jobs on `macos-latest`:
1. **Test**: `swift build -v` + `swift test -v`
2. **Lint**: SwiftLint + SwiftFormat via `./scripts/lint.sh`
3. **Example**: `cd Example && swift build -v`
