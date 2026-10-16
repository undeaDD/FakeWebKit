# Contributing

Thanks for your interest in FakeWebKit! Issues and pull requests are welcome.
By taking part you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

FakeWebKit is licensed under the [GNU GPL v3](LICENSE.md). By submitting a pull request you agree that your
contribution is published under the same license.

## Ground rules

- **WebKit parity only:** FakeWebKit is an alternative import for tvOS. Only add API that exists in WebKit,
  with the same names, signatures and behaviour, so the same code compiles against `WebKit` on iOS.
- **Additive changes:** existing FakeWebKit API must keep compiling. Prefer new overloads with
  `@_disfavoredOverload` on the old variant over changing a signature.
- **No dependencies:** UIKit and Foundation only. `UIWebView` is reached through the runtime, never imported.
- **tvOS only:** all code lives inside `#if os(tvOS)`.

## Development

- Xcode 26 or newer with a tvOS simulator runtime (Xcode > Settings > Components)
- Open `Package.swift` in Xcode, or run the tests from the terminal:

```bash
scripts/test.sh
```

`COVERAGE=1 scripts/test.sh` also prints line coverage, which has to stay at 95% or above.
`SIMULATOR_UDID=<udid>` picks a specific simulator. The tests run headless, no Simulator window opens.

## Git hooks, lint & tests

Run once after cloning:

```bash
scripts/setup-hooks.sh
```

- **pre-commit:** no em dashes or emoji in added lines, `swiftlint lint --strict` reports no violations
  (`.swiftlint.yml`) and all unit tests pass. Lint and tests only run when Swift code changed.
- **commit-msg:** no `Co-authored-by` trailers, no emoji, no em dashes in commit messages.
- The same text rules are checked for pull request titles, descriptions and commits in CI.
- Requirements: `brew install swiftlint`, Python 3 (ships with the Xcode command line tools).

## Pull requests

- One topic per PR, describe *why* in the description and link the WebKit documentation of the API
- Add tests for new API (`Tests/FakeWebKitTests`)
- Update the README feature list when public API changes
