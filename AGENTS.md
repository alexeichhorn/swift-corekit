# swift-corekit

Small building blocks for Swift backends: `@Schema`, `@EnvConfig`, retries, ordered JSON, logging, an HTTP client
and Hummingbird routes with an OpenAPI document. It is built test-first, and every change to it stays test-first.

## Test first

Every change, a feature, a bug fix or an API change, starts with its test. A new API is first written down in a test.
Every change lands as commits in this order:

1. `Test <feature>`: the tests alone. Run them and see them red for the reason you expect: a missing API fails the
   build, a behaviour gap fails an assertion. A test that is red for another reason, or green, is a finding: find out
   why before writing any code.
2. `Implement <feature>` or `Fix <bug>`: the code that turns them green, with the whole suite passing.
3. `Document <feature>`: its part of `README.md` and `docs/`.

A committed test changes only when the test itself was wrong. That is its own commit, `Fix test <name>`, and the
message says what was wrong.

## The kit baseline

Until `0.1.0`, the repo is rebuilt from an existing implementation, the kit. Its snapshot is the untracked folder
`.reference/kit`.

- Bring its code over as it is, feature by feature, each behind its tests. Its public API and behaviour are the
  baseline.
- A behaviour its README promises without a kit test gets that test written first.
- An improvement or a bug you notice becomes a GitHub issue; the code comes over unchanged.

## Public repo

Examples, tests and docs use generic domains: orders, products, users. Code, comments and docs describe the library
alone, never a project that uses it.

## Tests

- `swift test` runs everything: unit tests, macro expansion tests, and the HTTP and route tests, which start their own
  local servers.
- Macro expansion tests live in `Tests/CoreKitMacrosTests` and call `assertExpansion`.

## Checks

- Format before committing: `swift format --in-place --recursive Sources Tests Package.swift`. CI lints the same paths
  with `--strict`.
- CI builds and tests on Linux and macOS. The library deploys on Linux, and route discovery differs there: the route
  macros write records to an ELF section that `CCoreKitRoutes` reads, where macOS asks dyld. Use Foundation and the
  NIO libraries, and keep Apple-only frameworks behind `#if canImport`.
