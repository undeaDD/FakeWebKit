#!/bin/zsh
# Runs the unit tests headless on a tvOS simulator (no Simulator window).
# Usage: scripts/test.sh            other device: SIMULATOR_UDID=<udid> scripts/test.sh
#        COVERAGE=1 scripts/test.sh also prints line coverage for the FakeWebKit target.
set -euo pipefail
cd "${0:A:h:h}"

line="$(xcrun simctl list devices available | grep -m1 -E '^[[:space:]]+Apple TV' || true)"
udid="${SIMULATOR_UDID:-$(print -r -- "$line" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)}"
if [[ -z "$udid" ]]; then
  print -u2 "x No Apple TV simulator found (Xcode > Settings > Components > tvOS)."
  exit 1
fi

line="$(xcrun simctl list devices available | grep -m1 -F "$udid" || true)"
name="$(print -r -- "$line" | sed -E 's/^[[:space:]]+//; s/ \([0-9A-F-]{36}\).*//')"
print "> Running tests on $name ..."

log="$(mktemp -t fakewebkit-tests)"
result=".build/TestResults.xcresult"
rm -rf "$result"
if xcodebuild test \
    -scheme FakeWebKit \
    -destination "platform=tvOS Simulator,id=$udid" \
    -derivedDataPath .build/xcode \
    -enableCodeCoverage YES \
    -resultBundlePath "$result" \
    -quiet >"$log" 2>&1; then
  grep -E "Executed [0-9]+ tests" "$log" | tail -1 || true
  print "ok All tests passed"
else
  grep -E "error:|failed|Failing tests" "$log" | head -40
  print -u2 "x Tests failed (full log: $log)"
  exit 1
fi

if [[ -n "${COVERAGE:-}" ]]; then
  xcrun xccov view --report --only-targets "$result" | grep -E "FakeWebKit\.framework|FakeWebKit[[:space:]]" || \
    xcrun xccov view --report --only-targets "$result"
fi
