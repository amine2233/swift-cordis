#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

threshold_percent=15
baseline_file="docs/performance.md"

current="$(/usr/bin/xcrun swift run -c release cordis-bench 2>/dev/null)"
echo "$current"

warnings=0
while IFS=, read -r scenario n ns; do
    baseline="$(awk -F, -v s="$scenario" -v n="$n" '$1 == s && $2 == n { print $3 }' "$baseline_file")"
    if [[ -z "$baseline" ]]; then
        echo "NOTE: no baseline for $scenario,$n"
        continue
    fi
    if (( ns * 100 > baseline * (100 + threshold_percent) )); then
        echo "WARNING: $scenario,$n is $(( (ns - baseline) * 100 / baseline ))% slower than baseline ($baseline -> $ns ns/op)"
        warnings=$((warnings + 1))
    fi
done <<< "$current"

echo "bench-compare: $warnings warning(s); review only, never a failure."
exit 0
