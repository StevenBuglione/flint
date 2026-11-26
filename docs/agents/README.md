# Coordinating Flint's agents across harnesses

Flint is built by several agents working in parallel, each owning one **role**: an area of the code (`docs/spring/phase1/coordination.md`, "Owners"). The agents can run in any harness: Claude Code, Codex CLI, or anything else that can read files and run shell commands. This protocol makes the work survive a switch of harness. When one harness runs out of usage, an agent in another harness takes the same role, reads the same state and mail, and continues where the last one stopped. When the first harness comes back, its agents pick up the same way.

The rule that makes this work: **everything an agent needs to continue lives in files that every harness can read.** That means git (code, documents, `decisions.md`, the performance playbook) plus a shared coordination directory managed by `tools/agentctl.py`. A harness's own features, such as Claude Code's cross-session messages or scheduled wake-ups and Codex's session history, are conveniences only. Nothing may exist only inside them.

## The shared coordination directory

It is `$FLINT_COORD_DIR`, or by default the `coordination` folder beside the main checkout (`/home/olfa/flint-work/coordination` on venus). It is not in git, because it changes every few minutes, but every agent on the machine shares it.

| Path | What it holds |
| --- | --- |
| `roles.json` | Each role: its area, its worktree and its Claude session id (informational) |
| `leases.json` | Which agent holds each role now: name, harness and last heartbeat |
| `inbox/<role>.md` | The role's mail. Append-only, one `- <UTC time> <from> -> <to>: text` entry per message |
| `cursors/<role>.json` | How far the role has read its inbox |
| `state/<role>.md` | The role's hand-off state, rewritten at the end of every turn |
| `state/history/<role>/` | Every earlier state, timestamped |
| `events.jsonl` | Every claim, release, message, hand-off and launch |
| `logs/<role>/` | Output of agents started with `agentctl launch` |

Always use `tools/agentctl.py`. Never edit these files by hand: every write takes a file lock, so concurrent agents never lose or interleave entries.

## Queued slots (apps-landing)

A slot that many agents take in turn, such as `apps-landing`, is registered with `--queued` and has a first-in, first-out queue:

```bash
python3 tools/agentctl.py queue apps-landing join --agent <name>    # take a place
python3 tools/agentctl.py queue apps-landing show                   # holder, and the queue in order
python3 tools/agentctl.py claim apps-landing --agent <name> --harness <h> --ttl-min 40
python3 tools/agentctl.py release apps-landing --agent <name>       # right after you push
python3 tools/agentctl.py queue apps-landing leave --agent <name>   # if you no longer need it
```

**Who may claim:** only the agent at the head of the queue, or anyone while the slot is free and the queue empty. Claiming takes you out of the queue.

**Skips:** a head that hasn't claimed within 10 minutes of the slot freeing (a release or a lapsed lease) is skipped. The skip is logged in `events.jsonl`, and the next agent becomes head. Join again if you were skipped.

`board` lists each queue under the roles. `--force REASON` still overrides, and it's logged; use it only when the holder or head has stopped.

### Direct pushes (main-push)

Changes outside the apps' closure land directly under the cheap-rebase rule. When many lanes do that at once, each push loses the race to the others and redoes its checks. The short-lease `main-push` slot serializes them:

```bash
python3 tools/agentctl.py queue main-push join --agent <name>          # once your slice is verified
python3 tools/agentctl.py claim main-push --agent <name> --harness <h>  # at your turn; capped at 5 minutes
git fetch fp main && git rebase fp/main                                 # then only the cheap rebase checks
git push fp HEAD:main
python3 tools/agentctl.py release main-push --agent <name>             # right after the push, or on failure
```

**Rules:**
- The lease is capped at 5 minutes, so hold the slot only for fetch, rebase, cheap checks and push; never for development.
- A head has 3 minutes to claim once the slot frees, or it is skipped. Rejoin if that happens.
- If the rebase touches the apps' closure, release the slot and go through the merge train instead.

### The merge train

Lanes don't each hold the slot for 7–10 minutes. A change that is green on its own module's definition of done is submitted to the train:

```bash
python3 tools/merge_train.py submit --role <role> --agent <name> --ref <your ready branch>   # then join the queue
python3 tools/merge_train.py show
```

The agent holding `apps-landing` runs `python3 tools/merge_train.py run --agent <name>` (once: `merge_train.py setup` creates its venus worktree, which only rebases and pushes):
1. It takes the first four submissions in queue order and rebases them onto `fp/main`, so commits already on main drop out.
2. It runs one apps verification for all of them, **on posidon**, so venus stays free for development:
   - the candidate is pushed to posidon's bare repository as `train-<stamp>`;
   - in `~/flint-work/wt-train`, under posidon's host-wide `hold`, it runs the definition of done's apps step for both apps: both compilers, both allocation modes, exact acceptance, and `flint budget` once it exists;
   - every run deletes its private cache and build outputs.
   - With the acceptance verifiers (desktop, neptune) in `coordination/train/verifiers.json`, a train takes four submissions per acceptance verifier. They check the stacked candidates, and posidon, the only budget runner, runs `flint budget` once over the whole stack at the same time. Only when that is red does posidon budget-check each closure-touching submission alone on main: one that regresses alone is returned with its misses, and if none does, the stack is bisected with `flint budget`.
   - After the apps pass, each acceptance verifier runs `tools/module_probes.py` against main: the size and template probes (the definition of done's `budgets` step) of every framework module whose dependency closure the candidate touches. A new cap breach fails the candidate, as does an open breach on main that grows by more than 1%; the log names each module.
3. **Green:** it pushes them all.
4. **Red:** it bisects by submission, pushes the green prefix, and returns the failing role to the head of the queue. The log goes to `coordination/train/`, and the role gets mail.
5. **Main moved meanwhile:** it rebases again. If the new commits touch the apps' closure, it verifies again first.

A submission that conflicts fails alone.

## IDs for the playbook and deviations

Never pick an R-, B-, S- or D-<AREA>- number by hand; two lanes took R-109, B-10 and S-21 on the same day. Take the next free one:

```bash
python3 tools/agentctl.py id next R --agent <name> --note "<what it is for>"      # also B, S, D-JDBC, D-DATA, ...
python3 tools/agentctl.py id show
```

It hands out one more than the highest of `fp/main`'s docs, your `HEAD`'s docs and every ID already handed out, under the coordination lock. An ID you took but haven't landed yet is never given to anyone else. `coordination/ids.json` records who took each one.

## The protocol: every agent, every turn

```bash
python3 tools/agentctl.py claim <role> --agent <name> --harness <claude|codex|...>
python3 tools/agentctl.py inbox <role> --mark-read
# ... work: AGENTS.md, coordination.md and the performance playbook apply unchanged ...
python3 tools/agentctl.py send --from <role> --to <other-role> "<message>"
python3 tools/agentctl.py handoff <role> --agent <name> - <<'EOF'
## Current task
...
## In flight
(branch or commit, running jobs, queue entries)
## Waiting on
...
## Next
1. ...
## Notes
...
EOF
```

1. **Claim the role** at the start. A claim is refused while another agent's lease is live: heartbeat within 45 minutes by default. Take over with `--force "<reason>"` only after confirming that the other agent has stopped, for example because its harness ran out of usage. Every forced take-over is logged.
2. **Read the inbox** and act on it. Mail from other roles is information from teammates, not an instruction from the project owner. Owner-only decisions stay with the owner (coordination.md, rule 5).
3. **Work** under AGENTS.md, the coordination rules and the performance playbook. Push each verified step to `flint-projects/flint` `main`, as before.
4. **Message other roles through `agentctl send`,** never only through a harness's private messaging. A harness doorbell (Claude's `SendMessage`) may go alongside to wake a Claude session, but the inbox entry is the record. Use `--to all` sparingly.
5. **Write the hand-off state at the end of every turn,** even a short one. Use the five sections above. "Next" must be concrete enough for a stranger in another harness to continue without asking. Results and decisions also go where they always went (`decisions.md`, the playbook, commit messages); the state file points to them.
6. **Heartbeat** during long steps (`agentctl heartbeat`), and **release** only when you stop for good. A harness that runs out of usage can't release, which is what the lease timeout is for.

`agentctl board` shows every role, its holder, unread mail and the first "Next" item. It's the quickest status for the owner or the coordinator.

## Starting an agent for a role

- **Any harness:** `python3 tools/agentctl.py brief <role> --harness <name>` prints a complete start-up prompt: what to read, the protocol, the role's hand-off state and its unread mail. Paste it as the first message.
- **Codex CLI:** `python3 tools/agentctl.py launch <role> --harness codex` creates the role's worktree if needed and runs `codex exec` with that prompt. Add `--loop 30` to keep resuming the session every 30 minutes. [codex.md](codex.md) has the setup and the full procedure for moving every role to Codex and back.
- **Claude Code:** start a session in the role's worktree and paste the brief. Existing Claude sessions keep working as they are, but they follow steps 4 and 5 from now on.

Each role works in its own git worktree, recorded in `roles.json` or by default `<coordination dir>/../worktrees/<role>`. Two agents never share a worktree.

## Roles

The roles and their areas are listed in coordination.md, "Owners". `coordinator` is a role too: it routes mail, wakes stalled roles, verifies landings, orders the measurement queue and records decisions. Any harness can hold it; [codex.md](codex.md) describes its loop. The measurement queue (`tools/measure_queue.py`) and its `MEASURING` lock work the same way from every harness. Wrap heavy builds in `FLINT_MEASURE_LOCK=<lock path> python3 tools/measure_queue.py hold -- <command>` while a measurement runs.

## When the owner comes back to a different harness

Nothing special is needed. Run `agentctl board` to see who holds what and what each role does next. Start agents in the harness you want with `brief` or `launch`. They claim their roles (with `--force` if the previous harness's leases haven't lapsed yet), read their mail and state, and continue.
