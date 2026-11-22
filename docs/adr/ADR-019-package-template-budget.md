# ADR-019: What a package's template budget counts

Status: accepted on 2026-11-21 under the project owner's approval to complete Milestone 6. The owner may revert it; the closure count it replaces is still recorded for every package.

## Context

Every package has a hard ceiling of 2,000 template instantiations, measured on its feature probe build with `-vtemplates=list-instances`. `tools/measure_builds.py` summed every compiler invocation in that build, so a package's count included the compiles of all its dependency libraries.

Most instantiations in those dependency compiles come from druntime templates that any D code triggers: `RTInfo` for each aggregate, `hasIndirections` for each `new`, array comparison and concatenation lowerings. They are counted once in the dependency's own budget and again in every package that depends on it. A count measured at commit `eb914d9`, one compiler invocation per target, after removing Phobos from probe scaffolding (ADR-017):

| Definition | Packages over 2,000 |
| --- | ---: |
| Whole build closure (old) | 24 of 37 |
| Package library + its probe | 9 of 37 |
| Package library alone | 2 of 37 |

Under the old definition, web (3,747) was over its budget although its own library and probe compiles total 1,194. The other 2,553 belong to arena, reactor, conc, di, serde, validate and log, which are each measured under their own budgets.

## Decision

The budget counts the instantiations of the compiler invocations that compile the package's own modules (`packages/<name>/source`) and its feature probe (`packages/<name>/bench`). It does not count dependency library compiles.

- The probe compile stays in because that is where the package's generic API is instantiated with application types. That cost is real and belongs to the package.
- `measure_builds.py` records this as `template_instances` and the whole-closure count as `template_instances_closure`. `collect_evidence.py` re-derives both from the retained invocation receipts. Gates compare `template_instances` with the ceiling and keep the 10% growth rule.
- The milestone report shows both counts.

The ceiling itself is unchanged at 2,000.

## Consequences

- Each instantiation is charged to exactly one package's budget, so the gate measures the code a package owns rather than its dependency depth.
- A package that pulls heavy templates into its own compile, such as Phobos formatting, is still caught. This definition first exposed `style` (5,212 → 196 after removing one `std.format` call) and `test`.
- Closure counts remain visible, so growth in a deep dependency stack is still reported.
