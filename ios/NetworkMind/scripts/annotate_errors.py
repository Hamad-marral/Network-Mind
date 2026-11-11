#!/usr/bin/env python3
"""Turn xcodebuild compiler errors and XCTest failures into GitHub Actions annotations.

GitHub keeps at most 10 error annotations per step, so distinct errors are batched:
each annotation carries several errors separated by newlines (encoded as %0A).
"""
import re
import sys

ERROR_RE = re.compile(r"^(?P<file>/[^:]+):(?P<line>\d+):(?:\d+:)? error: (?P<msg>.+)$")
TEST_FAIL_RE = re.compile(r"^(?P<file>/[^:]+):(?P<line>\d+): error: (?P<msg>-\[.+\] : .+)$")
GENERIC_RE = re.compile(r"^(?:error|xcodebuild: error|.*: error): (?P<msg>.+)$")

MAX_ANNOTATIONS = 10
PER_ANNOTATION = 8


def short_path(path: str) -> str:
    marker = "ios/NetworkMind/"
    return path.split(marker, 1)[1] if marker in path else path


def escape(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def main(log_path: str) -> None:
    seen, items = set(), []
    with open(log_path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            match = TEST_FAIL_RE.match(line) or ERROR_RE.match(line)
            if match:
                item = f"{short_path(match['file'])}:{match['line']}: {match['msg']}"
            else:
                generic = GENERIC_RE.match(line)
                if not generic:
                    continue
                item = f"error: {generic['msg']}"
            if item not in seen:
                seen.add(item)
                items.append(item)

    if not items:
        return
    batches = [items[i:i + PER_ANNOTATION] for i in range(0, len(items), PER_ANNOTATION)]
    for number, batch in enumerate(batches[:MAX_ANNOTATIONS], start=1):
        print(f"::error title=Build errors {number}/{len(batches)}::" + escape("\n".join(batch)))


if __name__ == "__main__":
    main(sys.argv[1])
