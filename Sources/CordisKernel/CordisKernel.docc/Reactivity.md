# Reactivity: pending, active, restart

Plugins react to the services they inject; you never wire start order by hand.

## Lifecycle

A ``Fork`` is one application of a plugin in a context. Its ``Fork/Status`` moves through:

| Status | Meaning |
|---|---|
| `pending` | waiting for a required service |
| `loading` | `apply` is running |
| `active` | running |
| `failed` | `apply` threw; the scope was rolled back |
| `disposed` | unloaded |

## What triggers a transition

Each `provide` creates a new **occurrence** of a service. A fork remembers the occurrences it started with and compares them
on every change of a slot it injects (`ctx.update` mutates an occurrence in place and restarts nothing):

- required service missing: stop, back to `pending`;
- a service it injects was replaced (new occurrence): stop, then start again;
- an optional service appeared or vanished: restart;
- an unrelated slot changed: nothing happens.

Changes cascade. If A provides to B and B provides to C, removing A stops B (withdrawing B's service) which stops C.
Providing A again brings the chain back up.

## Re-entrancy

If a change arrives while a fork is already reconciling, it is queued and handled by the same loop instead of recursing.
Slots a fork provides itself are ignored for its own dependencies, so it cannot restart itself.

## Ordering

The kernel awaits every status change and event; there are no fire-and-forget tasks. A hot swap from `A` to `B` is always
`withdraw:A, stop:A, start:B, provide:B`, so behaviour is deterministic and testable.
