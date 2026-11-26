# Phase 2 porting guide for autonomous agents

Read this before porting any Spring module to Flint. It is the entry point; the detail lives in the documents it names. The owner decided that Phase 2 is ported by an autonomous agent steered by CI (decision 087f28a3), so **the checks are the authority**. If a check fails, the code is wrong until a reviewer agrees otherwise. Never weaken a check to make it pass.

## 1. What you are building

Flint is a D port of Spring Framework and Spring Boot. It must behave like Spring and beat Go on every build and runtime metric. Phase 1 proved this on three apps (B7: every gated metric under Go, with byte-identical responses against Java Spring Boot).

**Non-negotiable**
- **Names and behaviour are Spring's** (ADR-030):
  - same types, methods, annotations, defaults and configuration keys;
  - "Spring" becomes "Flint": `SpringApplication` → `FlintApplication`, `spring.*` → `flint.*`, with `spring.*` accepted as an alias.
  - Follow `docs/spring/api-mapping.md`. Every adapted element cites a rule ID; every deviation is listed.
- **Licences:**
  - each ported file carries its upstream path at the pinned tag, the upstream copyright line, and "Modified by the Flint authors";
  - every repo keeps Apache-2.0 `LICENSE` and the upstream `NOTICE` text;
  - the API gate checks the ported-file header marker.
- **`AGENTS.md` language rules:**
  - `@safe:` modules;
  - `@trusted` only in allowlisted `sys/` directories, at most 60 lines, with an adjacent `// SAFETY:`;
  - explicit selective imports;
  - hot engine paths `nothrow @nogc`;
  - structs for data;
  - no runtime reflection or construction by string name.
- **No new cryptography, HTTP/2, database or wire-protocol implementations.** Use the pinned wrappers.

## 2. The loop for one module

1. **Pick the module** from the manifest checklist (`flint api extract` output and the module's `api/mapping.json`). Port one module per worktree and branch.
2. **Read the upstream source and tests** at the pinned tag (Spring Framework v7.1.0, Spring Boot v4.2.0, matching portfolio tags).
3. **Port the upstream JUnit tests first.** Then port the code until they pass on DMD and LDC.
4. **Classify every public element** in `api/mapping.json`: ported, adapted (with a rule ID) or excluded (with a reason). The API gate fails on any unclassified element.
5. **Run the definition-of-done check** for the module: `python3 tools/gates.py --module <dir> --definition-of-done` (docs/spring/definition-of-done.md). Its eight steps: resolve, structural, api, quality, tests on DMD and LDC, upstream-tests (`<module>/upstream-tests.json`), budgets, and the apps that use the module. It must exit 0 for every slice you land. Elements and upstream test classes you have not ported yet are recorded as `deferred` with their phase, never left unclassified, so a partial module passes the normal check; `--release` fails while anything is deferred and is the "module complete" check. Deferred counts only shrink. The quality step is a ratchet: `policy/quality-baseline.json` only shrinks, and new code may add no findings. Then run `flint budget` for every app endpoint the module touches (m7 is building it). Both must pass. **You may never raise a budget.** The only exceptions are the pre-approved rules in decisions.md: `new-module-rule` (a new module's first caps), `api-growth-rule` (the measured cost of newly ported API in an API module) and `jdk-leaf-rule` (JDK leaves). Each needs its trailer and its evidence. If a regression is genuinely necessary, propose it to the coordinator with its evidence. A commit that raises a budget must carry a `Budget-Raise-Approved: <decision id>` trailer, and CI rejects one without it.
6. **Record what you learned** in `docs/spring/performance-playbook.md` in the same commit: a new R-, B- or S- rule with its evidence, or a correction.
7. **Land small, verified slices.**
   - Never amend or force-push shared `main`.
   - Rebase, re-run the checks, then push. If the rebase brought in nothing that touches your module's dependency closure or its apps, re-running the cheap steps is enough (decisions.md, 2026-11-26 01:10Z). A change that touches the apps' closure lands while holding the `apps-landing` slot (`agentctl claim apps-landing`), so two such changes never race.
   - Anything that touches a shared engine needs that engine owner's review before it lands: engine-reactor, engine-web, engine-servlet, engine-sql/jdbc, the arena/GC, Flint AOT, or Boot's autoconfigure core.

## 3. Performance: the rules that mattered most

All have evidence in the playbook (IDs in brackets). Violating any of them is the usual way a port loses to Go.

1. **Bytes per request decide tail latency.** Flint's GC stops the world for 100–300 µs, and requests that overlap a pause miss p99. The error paths only beat Go once their garbage was cut: the 404 went from 5,216 bytes to 0, the validation 400 from about 10 KB to about 6.7 KB. Treat every allocation on a request path as a cost; only objects user code sees may remain [R-1, R-73, R-103].
2. **Build per-type and per-configuration work once, at startup; never per request.** This covers parsed media types, mapping conditions, exception-handler resolvers, row-mapping plans, property writers, message templates, logger lookups and log strings [R-2, R-4, R-29, R-30, R-45, R-47, R-69, R-72, R-74, R-93].
3. **No lock on a lookup every request makes.** Publish immutable tables and read them without a monitor [R-7, R-64, R-70].
4. **Small collections are flat.** Store the first entries inline, size containers where the caller knows the size, keep keys and values in one block, and use no built-in associative arrays for long-lived registries [R-3, R-43, R-61, R-91, R-92, R-96].
5. **Keep objects inside GC size classes,** and move rarely used members out [R-73, R-80, R-87, R-99, R-102, R-103].
6. **Defer what a request may never read,** as Spring itself does: exception messages, the anonymous security token, optional properties [R-38, R-39, R-66, R-99].
7. **Prove at startup, guard per request, fall back to the generic path.** A request shape that every request takes deserves a Flint AOT fast path. Spring's objects are materialized only when something observes them. A failed proof always means "generic", never an error [R-23, R-24, R-25, R-60, R-78, R-98, R-100].
8. **Never throw where you can pass,** and give control-flow exceptions no backtrace [R-11, R-34, R-62].
9. **Engine memory never reaches the GC heap per request.** Pool engine-private storage behind a fresh façade with a generation check, and never pool user-visible objects [R-1, R-6, R-17, R-94, R-97].
10. **Do the work the reference does, and no less** (ADR-032 and ADR-033 parity). The Go comparator sends the same SQL as Java and closes connections where Tomcat does. Never make a benchmark faster by doing less than Spring [R-42, R-54, R-55].

**Binary size and build time:**
- no `std.format`, `std.conv`, `std.process`, `std.file` or `std.path` in framework code that every app links [S-2, S-5, B-2];
- generic APIs are thin façades over erased engines [B-1];
- generated code instantiates nothing per type that it can look up [B-3].

**Forbidden pattern (owner decision e170ffd0):** never give a class's metadata object a GC monitor (`new Mutex(typeid(X))`, `setSameMutex` with a TypeInfo). Use a private lock object; `synchronized (typeid(X))` is fine. The build gate FLINT-E0536 enforces it.

**Request and response lifetime (owner decision 8cb4beb8):** a request or response used after its exchange completed throws `IllegalStateException`, as in Tomcat with `RECYCLE_FACADES`. Copy what you need; never keep the façade.

## 4. Measuring and the shared machines

These rules exist because breaking them voided certification runs on 2026-11-25.

- **venus** is the only certification runner. **Every** command that compiles, links, tests or runs a gate on venus runs through hold, with the certification lock exported in the same shell:

  ```
  export FLINT_MEASURE_LOCK=/home/olfa/flint-work/flint/.claude/worktrees/jolly-mendeleev-ea37ba/.flint/measure/MEASURING
  python3 tools/measure_queue.py hold -- <command>
  ```

  That includes `tools/gates.py`, which compiles. Never time anything on venus yourself, and never wrap hold in `timeout`.
- **posidon** (olfa@10.10.10.12) is for timed diagnostics.
  - Work in your own worktree (`~/flint-work/wt-<role>`), never the shared checkout.
  - `source ~/flint-work/posidon.env`, and set `FLINT_HOME` to your worktree.
  - Builds go under `hold --`; timed runs under `timed --label <role> --`, at most 20 minutes each.
  - Delete your build outputs after each run.
- **Never kill processes by name** (`pkill dmd`). Stop only processes you started, by pid or by your worktree path. Stop every server and database cluster you start.
- **Dev loop:** deterministic counts via `tools/spring_instr.py`: instructions, allocations and bytes per request, at the O3 release link. Compare a change only against a base measured on the same machine with the same link mode.
- **Never claim a number you did not measure,** and never compare numbers across machines. Report base and candidate commits, the machine, and the exact command.

## 5. Stop and ask (owner decisions)

Stop, and ask the coordinator, before:
- any D language or compiler change;
- raising a budget or weakening a gate or check;
- changing a workload, TLS profile, comparator or benchmark rule;
- any change to druntime or the shared toolchain;
- deleting another session's work;
- creating or deleting repositories;
- any outward-facing action.

The coordinator takes these to the owner. Since 2026-11-26 the coordinator approves most of them itself, on review, under the owner's standing approval (decisions.md); repositories, outward-facing actions, deleting others' work, language or toolchain changes, and certified-workload changes still go to the owner.

## 6. Where to read more

- `AGENTS.md`: operating rules.
- `docs/adr/ADR-030-flint-is-a-spring-port.md`: the port's contract.
- `docs/spring/api-mapping.md`: the Java → D rulebook.
- `docs/spring/performance-playbook.md`: every measured performance rule and the porting checklist (section 6).
- `docs/spring/phase1/gc.md`: what the collector costs and which levers worked.
- `docs/spring/phase1/decisions.md`: every decision, with its reason.
- `docs/spring/phase1/coordination.md`: how sessions share machines and land work.
