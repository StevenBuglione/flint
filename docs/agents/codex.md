# Running Flint's roles in Codex CLI

This is the procedure for moving the work to [Codex CLI](https://learn.chatgpt.com/docs/non-interactive-mode), for example when Claude Code usage runs out, and for moving it back. It relies on the harness-neutral protocol in [README.md](README.md).

## What Codex brings, and what replaces the Claude-only features

| Need | Claude Code | Codex CLI |
| --- | --- | --- |
| Project instructions | `AGENTS.md` | `AGENTS.md`. Codex reads it natively, from the repository root down to the working directory, up to `project_doc_max_bytes` (default 32 KiB; Flint's is about 9 KiB). |
| Messages between roles | `SendMessage` (a doorbell) plus `agentctl send` | `agentctl send` and `agentctl inbox` |
| Wake-ups and loops | `ScheduleWakeup`, `/loop` | `agentctl launch --loop N`, which re-runs `codex exec resume --last` every N minutes |
| Resuming context | the session transcript | `codex exec resume --last` in the role's worktree, plus the hand-off state |
| Parallel work | sessions in their own worktrees | one worktree per role (`agentctl worktree <role>`) |

## One-time setup

1. **Codex CLI is installed** (`codex --version`; 0.171 on venus) and signed in.
2. **Permissions.** Agents must write in their worktree, in the shared coordination directory and in `.flint/` measurement state, and must reach GitHub to push.
   - venus's `~/.codex/config.toml` already uses `sandbox_mode = "danger-full-access"` with `approval_policy = "never"`, which allows all of that.
   - For a tighter setup, copy [codex/flint.config.toml](codex/flint.config.toml) to `~/.codex/flint.config.toml` and pass `--profile flint` to `agentctl launch`. It uses `workspace-write` with network access and the Flint work tree as a writable root.
3. **Trust.** Codex loads project `.codex/` configuration only for trusted projects. venus trusts `/home/olfa`, which covers every Flint worktree. Nothing project-specific is needed.
4. **Git push.** Agents push with the same SSH key as today (`git@github.com:flint-projects/<repo>.git`). Check with `git -C <worktree> push --dry-run fp HEAD:main`.

## Moving a role to Codex

```bash
cd /home/olfa/flint-work/flint
python3 tools/agentctl.py board                         # who holds what; state age; unread mail
python3 tools/agentctl.py launch web-http --harness codex --dry-run   # check the worktree and command
nohup python3 tools/agentctl.py launch web-http --harness codex --loop 30 >/dev/null 2>&1 &
```

- `launch` creates the role's worktree from `flint-projects/flint` `main` if it doesn't exist, then runs `codex exec --cd <worktree>` with the role's brief: protocol, state and unread mail.
- With `--loop N`, it then runs `codex exec --cd <worktree> resume --last "<continue>"` every N minutes. Each role has its own worktree, so `--last` always resumes that role's session.
- Output goes to `<coordination dir>/logs/<role>/`.
- The agent's first act is `agentctl claim`. If a Claude session still holds the role and is truly stopped, the agent takes over with `--force "<reason>"`, and the take-over is logged.
- To run Codex interactively instead: `codex --cd "$(python3 tools/agentctl.py worktree web-http)" "$(python3 tools/agentctl.py brief web-http --harness codex)"`.

To move everything, launch each role in `agentctl roles` with its own `--loop` (30 minutes suits most roles). Launch `coordinator` too. Stagger the starts by a minute so they don't all build at once. On venus the measurement lock still serialises timed runs.

## The coordinator role in Codex

The coordinator's loop is the same in every harness. Each tick:

1. `agentctl inbox coordinator --mark-read`, then `agentctl board`.
2. Check the measurement queue:
   - `tail` the watcher log under the measuring worktree's `.flint/measure/watch.log`;
   - is `MEASURING` held?
3. Check what landed: `git fetch fp main && git log --oneline <last-seen>..fp/main`. Verify that what roles report is really on `main`.
4. Route and decide:
   - answer roles' questions within the documents' rules;
   - send owner-only questions to the owner (coordination.md, rule 5) and don't decide them;
   - record decisions in `docs/spring/phase1/decisions.md`;
   - keep runtime work ahead of build work in the queue while runtime is the Phase 1 blocker.
5. Wake stalled roles. A role whose lease lapsed with work left gets a `send` with its next step, or a `launch` if no agent runs it.
6. Write the coordinator's hand-off state.

Run it with `agentctl launch coordinator --harness codex --loop 30`.

## Moving back to Claude Code

Stop the Codex loops (`pkill -f "agentctl.py launch"`; a Codex turn in progress finishes first). Then, for each role:
- start or resume a Claude session in the role's worktree;
- paste `agentctl brief <role> --harness claude`;
- the session claims the role (with `--force` if the Codex lease hasn't lapsed) and continues from the state and mail.

Claude sessions keep using `SendMessage` as a doorbell, but always write the inbox entry and the hand-off state as well.

## Checks before relying on it

- `python3 -m unittest tests.test_agentctl`: the store's locking, leases, mail and hand-off history.
- `python3 tools/agentctl.py launch <role> --harness codex --dry-run`: the exact command, without running it.
- `python3 tools/agentctl.py board`: every role should show a recent state age. A role whose state is hours old wasn't writing hand-offs, and an agent from another harness would start it blind.
