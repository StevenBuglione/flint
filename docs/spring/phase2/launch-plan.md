# Phase 2 launch plan: gpt-6.2-sol lanes

The owner started Phase 2 on 2026-11-25 (decisions.md, 23:50Z; earlier 087f28a3). Phase 2 ports the rest of the original Spring library work with autonomous agents running gpt-6.2-sol under Codex CLI, steered by failing checks rather than by review. Every lane follows [porting-guide.md](porting-guide.md), so read that first. This page says who ports what, in what order, who reviews it, and how the lanes run.

## Lanes

There are three lanes now. Each is an `agentctl` role with its own worktree at `/home/olfa/flint-work/worktrees/<role>`. They own disjoint directories, so they rarely conflict.

| Role | Ports, in order | Directories it owns | Reviewers for shared code |
|---|---|---|---|
| `sol-data` | 1. Spring Data Commons: finish the deferred elements of `api/data-commons`. 2. Spring Data JDBC and Relational (`data-jdbc` repo): `CrudRepository`/`ListCrudRepository` over JDBC, derived queries compiled by Flint AOT, `@Query`, aggregates, auditing. 3. Boot's `flint-boot-data-jdbc` auto-configuration and its starter. | `framework/data-commons`, new `data-jdbc/*` packages, `boot/module/flint-boot-data-jdbc*` | data-access (engine-jdbc, jdbc, tx); flint-aot (generated repositories) |
| `sol-security` | 1. Spring Security core and crypto beyond petclinic's subset: password encoders on the pinned wrappers, user details, providers, events. 2. Security web and config: form login, logout, session management, CORS, `RequestMatcher`s, method security. 3. The OAuth2 resource server (JWT) on the pinned crypto wrappers. No new cryptography. | `security/*`, `boot/module/flint-boot-security*` | web-http (filters, servlet); framework-core (the `@PreAuthorize` advisor and AOP) |
| `sol-context` | 1. spring-context features: the cache abstraction with `@Cacheable`, `@CacheEvict` and `@EnableCaching`; `@Scheduled` and `TaskScheduler`; `@Async`; `@Retryable` where Spring has it. 2. spring-web's clients: `RestClient`, then `HttpServiceProxyFactory` (`@HttpExchange`). 3. Boot auto-configuration for each: cache, task execution and scheduling, the HTTP client. | new modules under `framework/` for the features above, the matching `boot/module/flint-boot-*` | framework-core (beans, context, `engine-aot`); web-http (`RestClient` over engine-http); boot (auto-configuration core) |

**Wave 2** starts when each wave-1 lane has landed its first module through the definition of done with no reviewer rejection. The coordinator launches it.
- `sol-observability`: Actuator endpoints and Micrometer (`io.micrometer.core.instrument`, 2,280 deferred elements).
- `sol-template`: SpEL compiled to D by Flint AOT, then Thymeleaf.
- `sol-jpa`: the JPA engine ported from Hibernate ORM.
  - **Start with an ADR draft.** The coordinator takes the ADR to the owner. No code lands before the owner approves it.
  - Classic PetClinic follows the JPA engine.
- `sol-ai`: `flint-ai` takes over the ai and mcp packages.

**Phase 3**, unchanged from the plan, needs owner go-ahead per item: WebFlux and Reactor, WebSocket and STOMP, Kafka, AMQP, Redis, MongoDB, Batch, Integration, the cloud family, Session and GraphQL.

## How a lane works

1. **Pick the next element group** from the lane's order. Use `flint api coverage --repo <repo>` and the module's entries in `api/<repo>/mapping.json` that are `excluded` with category `deferred` and phase 2.
2. **Follow the porting guide's loop:**
   - port the upstream JUnit tests first;
   - classify every element;
   - pass `python3 tools/gates.py --module <dir> --definition-of-done`;
   - add a playbook rule for each performance lesson;
   - land small, verified slices on `fp main`.
3. **`flint budget`.** When m7 lands it (it is announced in the lane's inbox), every endpoint a lane's module touches must pass it before landing. Never raise a budget; propose a raise to the coordinator with evidence.
4. **Changes to shared engines** need a reviewer from the table before landing. The shared engines are:
   - engine-reactor, engine-web, engine-servlet, engine-http, engine-sql/jdbc and engine-aot;
   - the arena and GC;
   - Flint AOT;
   - Boot's auto-configuration core;
   - `policy/*`.

   To ask for a review: `python3 tools/agentctl.py send --from <role> --to <reviewer> "<commit or branch, what, why>"`. Then keep working on something else. If there's no answer in 30 minutes, coordination.md rule 3 applies: make the smallest reversible change, in its own commit, and tell the reviewer.
5. **Package registration** in `policy/packages.json`, `policy/framework.json` and `policy/repos.json` goes in a commit of its own, with m7 (the integration owner) told through `agentctl send`. On rebase conflicts in policy files, keep both sides' entries.
6. **Everything on venus runs under `hold`,** including `gates.py`, `dub`, `flint` and `ci.py`:

   ```
   export FLINT_MEASURE_LOCK=/home/olfa/flint-work/flint/.claude/worktrees/jolly-mendeleev-ea37ba/.flint/measure/MEASURING
   python3 tools/measure_queue.py hold -- <command>
   ```

   While no window is open, hold costs nothing. When a window opens (overnight certification, or on request), held work pauses and resumes by itself. Never time anything on venus, and never use posidon without a reservation in your inbox.
7. **Stop and ask** for anything on the porting guide's list (section 5). Write the question to the coordinator, and continue with another element group meanwhile.
8. **Write the hand-off state at the end of every turn** (`agentctl handoff`). It must be concrete enough for another agent to continue without asking.

## Measurement in Phase 2

- **The dev loop is deterministic:** `tools/spring_instr.py` counts, the allocation gates, and `flint budget` once it lands. These need no quiet window.
- **Certification on venus:**
  - It runs overnight in natural quiet, or when the owner asks. It never blocks a lane.
  - The proof-harness role schedules it and names baselines as before: B8 and onward.
  - A certified regression against Go goes to the lane that caused it, as its next item.

## Launching and stopping

The coordinator launches each lane with the Codex profile `flint-sol`, defined in `~/.codex/config.toml` with model gpt-6.2-sol:

```bash
cd /home/olfa/flint-work/flint
nohup python3 tools/agentctl.py launch sol-data --harness codex --profile flint-sol --agent sol-data-1 --loop 20 >/dev/null 2>&1 &
```

- Stagger lane starts by a few minutes so their first builds don't collide.
- **Output** goes to `/home/olfa/flint-work/coordination/logs/<role>/`.
- **To stop one lane,** kill its `agentctl.py launch` process by pid. The Codex turn already in progress finishes first.
- **Never stop a lane by process name.**

## The coordinator's checks on lanes

Every tick, the coordinator:
- reads `agentctl board`;
- verifies each lane's reported landings on `fp main` (`git show --stat`);
- spot-checks one landed slice per lane: definition of done, classification honesty, and tests that exercise behaviour rather than restating it;
- routes review requests;
- wakes stalled lanes.

A lane that lands a slice violating the porting guide gets the revert, or the fix, as its next item. A lane that repeatedly fails the same rule is stopped, and the case goes to the owner.
