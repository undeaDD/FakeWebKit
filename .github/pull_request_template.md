## What does this change?

<!-- Short description, link related issues: "Closes #123" -->

## WKWebView parity

<!-- Which WebKit API does this add or change? Link the Apple documentation. -->

## Checklist

- [ ] Only adds API that exists on `WKWebView` / WebKit, with the same names and signatures
- [ ] Existing FakeWebKit API keeps compiling (additive changes only)
- [ ] `swiftlint lint --strict` reports no violations
- [ ] `scripts/test.sh` passes and coverage stays at 95% or above (`COVERAGE=1 scripts/test.sh`)
- [ ] README updated if public API changed
- [ ] Title, description and commits contain no em dashes, emoji or Co-authored-by trailers
