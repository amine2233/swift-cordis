# Performance baseline

These numbers are same-machine regression evidence only. They are never a target, a throughput claim,
or comparable across machines (Proposal 0010).

## Running

    mise run bench                        # runs scripts/bench-compare.sh
    swift run -c release cordis-bench 10  # raw output, optional sizes as arguments

Output is one `scenario,n,ns_per_op` line per run. `ns_per_op` is the total time divided by `n`.

- `load`: load `n` plugins with no dependencies.
- `provide`: provide a service that `n` pending plugins require.
- `update`: update a provider plugin, restarting its `n` dependents.

`scripts/bench-compare.sh` prints a WARNING for any scenario more than 15% slower than the lines below and
always exits 0: a crossing means review, not failure. Small `n` is dominated by warm-up and is noisy.
Never run it in shared CI.

## Baseline

- Machine: Apple M5 Pro
- OS: macOS 27.0.1
- Swift: Apple Swift version 6.4 (swiftlang-6.4.0.34.1), release build
- Recorded: 2026-10-24

```text
load,10,14220
provide,10,1883
update,10,1308
load,100,774
provide,100,697
update,100,905
load,1000,730
provide,1000,670
update,1000,862
```
