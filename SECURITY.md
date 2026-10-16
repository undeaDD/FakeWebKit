# Security Policy

FakeWebKit loads arbitrary web content in apps on tvOS, so security issues are taken seriously.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

**Please do not open a public issue.**

Report vulnerabilities privately via [GitHub Security Advisories](https://github.com/undeaDD/FakeWebKit/security/advisories/new).
You'll get a response as soon as possible; please allow time for a fix before any disclosure.

Helpful details:

- FakeWebKit version, tvOS version and device
- steps to reproduce / proof of concept (a minimal HTML page helps)
- impact (e.g. a page can call message handlers it shouldn't reach, read cookies of other hosts)

## Scope

In scope: the JavaScript message bridge (`window.webkit.messageHandlers`), user script injection,
cookie and website data handling, and navigation policy decisions.

Out of scope: bugs in the system `UIWebView` itself, and App Store review outcomes caused by its use
(see the notice in the README).
