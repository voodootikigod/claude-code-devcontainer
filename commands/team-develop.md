# Team Develop

Orchestrate parallel implementation teams using Claude Code Agent Teams (primary) or subagents (fallback). Each team is a pair: implementer + domain specialist reviewer, working in an isolated git worktree.

## Arguments

- `--teams=N` (default: 3) — Number of parallel teams (1-5)
- `--plan=FILE` (default: PLAN.md) — Plan file to read
- `--strategy=staggered|parallel|sequential` (default: staggered)
- `--merge=rebase|pr|direct` (default: rebase)
- `--scope=all|p1|p1+one-feature|custom` (default: all)
- `--build-gate=true|false` (default: true)
- `--mode=auto|teams|subagents` (default: auto)

## Mode Selection

Check if Agent Teams is available. If `auto`: use Agent Teams when enabled, otherwise prompt user to enable or fall back to subagents.

---

## Phase 0: Permissions Preflight

Before any real work begins, run a dry-run sequence that exercises every tool and operation the teams will use. This surfaces all permission prompts upfront so the user can approve them once, preventing mid-workflow permission blocks.

### Steps

1. **Announce**: "Running permissions preflight — you may see several permission prompts. Approve each one to ensure smooth team execution."

2. **Test core tool permissions** (run these sequentially, each is a no-op or read-only):

   | Operation | Test command | Purpose |
   |-----------|-------------|---------|
   | Bash execution | `echo "preflight: bash ok"` | Verify shell access |
   | Git operations | `git status` | Verify git access |
   | File read | Read the plan file | Verify Read tool |
   | File write | Write a temp file `.preflight-test` with "ok", then delete it via `rm .preflight-test` | Verify Write + cleanup |
   | File edit | (covered by write test) | Verify Edit tool |
   | Glob/Grep | `Glob("**/*.md")` | Verify search tools |
   | Worktree creation | `git worktree add /tmp/worktrees/preflight --detach HEAD` then `git worktree remove /tmp/worktrees/preflight` | Verify worktree permissions |
   | Branch operations | `git branch preflight-test && git branch -d preflight-test` | Verify branch create/delete |
   | Build commands | `pnpm typecheck --help` or equivalent no-op | Verify build tool access |
   | Agent/Team spawn | Spawn a minimal agent: `Agent(prompt="echo preflight ok", description="preflight test")` | Verify agent spawning |

3. **Test mode-specific permissions**:
   - **Agent Teams mode**: Create a team with one no-op teammate, verify delegate mode works, then clean up
   - **Subagent mode**: Launch one Task with a no-op prompt, verify completion

4. **Test beads/bd access** (if using beads):
   ```bash
   bd list --status=open --limit=1
   ```

5. **Report results**:
   ```
   ✓ Permissions preflight complete — all operations allowed
   ```
   Or if any failed:
   ```
   ✗ Permissions preflight FAILED:
     - [operation]: [error/denial reason]
   Action: Please approve the denied permissions and re-run, or adjust your permission settings.
   ```

6. **Abort if critical permissions denied**: If Bash, Agent spawn, or worktree operations are denied, stop and report — the workflow cannot proceed without them.

### Why This Phase Exists

Without preflight, the first team spawn triggers permission prompts that can:
- Block an agent waiting for approval while others race ahead
- Cause timeouts if the user isn't watching
- Create confusing state where some teams started and others didn't

By front-loading all prompts, the user approves once and the entire workflow runs uninterrupted.

---

## Phase 1: Plan & Setup

1. Read the plan file
2. Run `bd ready` (unblocked issues) and `bd blocked` (dependency graph)
3. Select issues based on `--scope`:
   - `p1` = P1 priority unblocked issues only
   - `p1+one-feature` = P1 foundation + one complete feature track
   - `all` = all issues respecting dependency order
4. For each team, select a reviewer specialist based on issue domain:

| Issue domain | Reviewer focus |
|-------------|---------------|
| Shared types, schemas, constants | Type design, backwards compat, schema validation |
| Sandbox, snapshots, templates | API usage, writeFiles, extendTimeout, snapshot lifecycle |
| Workflow steps, hooks, cron, events | Step directives, bundle isolation, devalue safety, hook placement |
| API routes, serverless functions | Routing, timeouts, streaming, auth |
| UI components, forms | Accessibility, Geist tokens, component patterns |
| Next.js pages, layouts, routing | App Router patterns, server/client components |
| Database, Redis, Blob, storage | Connection pooling, schema design, storage patterns |

5. Create worktrees:
```bash
git branch team-1/issue-id main
git worktree add /tmp/worktrees/team-1 team-1/issue-id
# repeat for each team
```

6. Mark issues in_progress: `bd update <id> --status=in_progress`

### Beads/Dolt Isolation Rules

Worktrees are created in `/tmp/worktrees/` (outside the workspace) to prevent Dolt database corruption. Additional rules:

- **NEVER run `bd` commands from a worktree** — only the lead runs beads from the main working tree (`/workspace`)
- **Team agents must NOT interact with beads directly** — no `bd close`, `bd update`, `bd show` from worktrees
- **Only the lead** manages issue status (open/close/update) from the main tree
- **If `bd` errors occur**, restart the Dolt server: `bd sql-server stop && bd sql-server start`

---

## Phase 2: Execute — Agent Teams Mode

The current session becomes the **lead** in delegate mode (Shift+Tab) — coordination only, no code writing.

### Spawn Teams

```
Create an agent team. Use delegate mode. Require plan approval for implementers.

Team 1 (foundation — worktree /tmp/worktrees/team-1):
  - "team1-impl": Implementer for issue {id} — {title}.
    Working directory: {absolute_worktree_path}. Branch: team-1/{issue_id}.
    {description}. {notes}. {plan_section}.
    Work ONLY in the worktree. Do NOT run any `bd` or beads commands.
    Run pnpm typecheck && pnpm build before done.
    Commit changes. Do NOT push or merge.
  - "team1-review": {domain} specialist reviewer for team1-impl.
    Working directory: {absolute_worktree_path}.
    Review with git diff main. Check correctness, API alignment, bundle safety, patterns.
    Message team1-impl directly with corrections. Iterate until satisfied.

Team 2 (feature — worktree /tmp/worktrees/team-2):
  [same pattern]

Team 3 (feature — worktree /tmp/worktrees/team-3):
  [same pattern]
```

### Staggered Execution

**Wave 1** — Foundation team implements, others prep in plan mode:
- team1-impl: Implements foundation (types, schemas, shared code)
- team1-review: Reviews and messages corrections directly to team1-impl
- team2-impl, team3-impl: Explore codebase, draft plans (read-only)

**Wave 2** — After Team 1 merges into main:
- Lead merges Team 1's branch (see Merge Protocol below)
- Lead rebases remaining worktrees: `cd /tmp/worktrees/team-N && git rebase main`
- Lead approves team2-impl and team3-impl plans → they begin implementation
- team2-review, team3-review activate

**Wave N+** — Continue until scope exhausted.

### Key Agent Teams Features

- **Delegate mode** (Shift+Tab): Lead coordinates only
- **Plan approval**: Implementers plan first, lead approves before coding
- **Direct messaging**: Reviewers message implementers directly for fix cycles
- **Shared task list**: Create tasks matching beads issues with dependencies
- **TaskCompleted hook**: Instruct lead "Only mark tasks complete after pnpm typecheck && pnpm build passes"
- **TeammateIdle**: Idle teammates claim next unblocked task

### Fix Cycle (Implementer ↔ Reviewer)

1. Implementer commits → reviewer runs `git diff main`
2. Reviewer messages implementer directly with corrections
3. Implementer fixes, re-commits → reviewer re-reviews
4. Max 3 cycles, then escalate to lead
5. This happens WITHOUT the lead's involvement

---

## Phase 2 (Alt): Execute — Subagent Fallback

If Agent Teams unavailable, use Task tool. The main session manages everything.

### Launch Teams

Launch implementers in parallel (one Task per team):
```
Task(subagent_type="general-purpose", prompt="Implement issue {id} in worktree at {path}. ...")
```

After implementers complete, launch validators in parallel:
```
Task(subagent_type="squadV:{specialist}:{specialist}", prompt="Review issue {id} in worktree at {path}. ...")
```

### Fix Cycle (Subagent)

Lead reads validator output → launches new implementer Task with corrections → re-validates. Max 3 cycles. Lead relays all messages (no direct communication).

### Build Gate

Lead runs manually: `cd <worktree> && pnpm typecheck && pnpm build`

---

## Phase 3: Merge Protocol (Sequential Rebase)

For each completed team, in dependency order:

### 1. Rebase onto main
```bash
git checkout team-N/issue-id
git rebase main
```
If conflicts: **lead resolves** (not teams). Prefer additive resolution. After resolving: `git add <files> && git rebase --continue`

### 2. Fast-forward main
```bash
git checkout main
git merge --ff-only team-N/issue-id
```

### 3. Verify build on main
```bash
pnpm typecheck && pnpm build
```
If broken: `git reset --hard HEAD~N` and debug.

### 4. Rebase remaining branches
```bash
cd /tmp/worktrees/team-N && git rebase main
# for each remaining team
```

### 5. Close issue
```bash
bd close <issue-id>
```

### Merge Order Rules
1. Foundation first (no blockedBy → merges first)
2. Shared packages before apps
3. Within same tier: first done, first merged

### Conflict Resolution
| File type | Strategy |
|-----------|----------|
| types.ts / schemas.ts | Combine both additions |
| index.ts (barrel) | Merge both exports |
| App-specific files | Should not conflict |
| package.json | Combine deps, keep higher versions |

---

## Phase 4: Cleanup

1. Shut down all teammates (Agent Teams) or wait for Tasks to complete (subagents)
2. Clean up team: tell lead "Clean up the team"
3. Remove worktrees: `git worktree remove /tmp/worktrees/team-N`
4. Delete branches: `git branch -d team-1/issue-id team-2/issue-id team-3/issue-id`
5. Sync: `bd sync`
6. Push: `git push`
7. Verify: `git status` shows clean tree

---

## Lead Coordination Checklist

At each wave boundary:
- [ ] All teammates idle or shut down
- [ ] Build gate passed for each team
- [ ] Merged in dependency order (foundation first)
- [ ] Rebased remaining worktrees onto new main
- [ ] Beads updated: `bd close` completed, `bd update --status=in_progress` next wave
- [ ] Context check — compact ONLY now if needed (never during active work)
- [ ] Spawned/messaged teammates for next wave

### Compaction Rules
- **Compact only at**: wave boundaries, after merge sequences, before spawning next wave
- **Never compact when**: teammates active, merge in progress, build gate running
- **After compaction**: re-read `bd list --status=open` and `git worktree list`

---

## Error Handling

- **Teammate stops**: message to resume, spawn replacement if unresponsive
- **Build fails 3x**: reviewer helps debug, then lead investigates, then escalate to user
- **Merge conflicts**: lead resolves directly, runs build gate after, prefers additive resolution
- **Dependency cycle**: stop and report to user immediately
