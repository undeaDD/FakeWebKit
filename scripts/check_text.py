#!/usr/bin/env python3
"""Text rules for commits, pull requests and files: no em dashes, no emoji, no co-author trailers.

Usage:
  check_text.py --message <file>   commit message (comment lines are ignored)
  check_text.py --stdin            PR title / body / commit messages piped in
  check_text.py --staged           lines added in the staged diff
  check_text.py --files <paths..>  whole files
"""
import re
import subprocess
import sys

EM_DASH = "—"
EMOJI = re.compile(
    "[\U0001F000-\U0001FAFF⌀-⏿☀-➿⬀-⯿️‍]"
)
CO_AUTHOR = re.compile(r"(?im)^\s*co-authored-by\s*:")


def problems_in(text, allow_co_author=False):
    problems = []
    if not allow_co_author and CO_AUTHOR.search(text):
        problems.append("contains a Co-authored-by trailer")
    if EM_DASH in text:
        problems.append("contains an em dash (U+2014), use '-' instead")
    found = sorted(set(EMOJI.findall(text)))
    if found:
        codes = " ".join("U+%04X" % ord(c) for c in found)
        problems.append("contains emoji or symbols: " + codes)
    return problems


def staged_additions():
    diff = subprocess.run(
        ["git", "diff", "--cached", "-U0", "--no-color", "--diff-filter=ACMR"],
        capture_output=True, text=True, encoding="utf-8", errors="replace", check=True,
    ).stdout
    current, results = None, {}
    for line in diff.splitlines():
        if line.startswith("+++ "):
            current = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("+") and current:
            results.setdefault(current, []).append(line[1:])
    return results


def report(label, problems):
    print("x %s rejected:" % label, file=sys.stderr)
    for problem in problems:
        print("  - " + problem, file=sys.stderr)


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    mode, failed = argv[1], False
    if mode == "--message":
        with open(argv[2], encoding="utf-8") as handle:
            lines = [l for l in handle.read().splitlines() if not l.startswith("#")]
        problems = problems_in("\n".join(lines))
        if problems:
            report("Commit message", problems)
            failed = True
    elif mode == "--stdin":
        problems = problems_in(sys.stdin.read())
        if problems:
            report("Text", problems)
            failed = True
    elif mode in ("--staged", "--files"):
        if mode == "--staged":
            sources = staged_additions()
        else:
            sources = {}
            for path in argv[2:]:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    sources[path] = handle.read().splitlines()
        for path, lines in sorted(sources.items()):
            if path.endswith(("check_text.py", ".png", ".jpg")):
                continue
            problems = problems_in("\n".join(lines), allow_co_author=True)
            if problems:
                report(path, problems)
                failed = True
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
