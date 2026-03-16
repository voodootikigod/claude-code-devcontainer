# Auto Develop

Continuously execute phases of work until all beads issues are resolved. Wraps `/next-phase` and `/team-develop` in a completion-based loop with safety rails. Designed for unattended operation — no user confirmation between phases.

## Arguments

- `$ARGUMENTS` — Optional flags:
  - `--max-phases=N` (default: 5) — Hard stop after N phases
  - `--teams=N` (default: 2) — Max parallel teams per phase (capped lower than manual for safety)
  - `--scope=p1|p1p2|all` (default: p1p2) — Priority filter. P3+ skipped by default.
  - `--pause-on-failure` — Stop on first build/merge failure instead of retrying
  - `--dry-run` — Plan all phases without executing; show what would happen

---

## Phase Loop

```
phase_number = 1
last_ready_ids = []
max_phases = parse --max-phases or 5

LOOP:
  if phase_number > max_phases → STOP("Max phases reached")

  ready_issues = `bd ready`
  if ready_issues is empty → STOP("All work complete")

  current_ids = extract issue IDs from ready_issues
  if current_ids == last_ready_ids → STOP("Stuck: same issues ready as last phase, no progress made")

  last_ready_ids = current_ids

  RUN PHASE(phase_number, ready_issues)

  if phase failed and --pause-on-failure → STOP("Phase failed")
  if phase failed → RETRY PHASE once, then STOP if still failing

  COMPACT context (mandatory between phases)
  Re-read state: `bd ready`, `bd list --all`, `git log --oneline -5`

  phase_number += 1
  GOTO LOOP
```

---

## Step 1: Assess Work (per phase)

Run:
```bash
bd ready
bd list --all
bd blocked
```

From the output:
1. Filter issues by `--scope` (default: P1 and P2 only)
2. Select only **ready** (unblocked) issues
3. Map dependency graph for merge ordering
4. Cap selection at 2× `--teams` issues (default: 4 issues for 2 teams)

## Step 2: Plan Phase (auto-approved)

Group issues into teams using these rules:

| Grouping Principle | Rationale |
|-------------------|-----------|
| Same package/directory | Minimizes merge conflicts |
| Related functionality | Shared context reduces ramp-up |
| Independent file sets | Enables true parallel work |
| Balanced workload | Similar complexity per team |

Determine merge order:
1. Foundation/shared code first
2. Packages before apps
3. Independent changes in any order

**Log the plan** — print it to output so it's visible in conversation history, but do NOT wait for confirmation. Proceed immediately.

```
## Auto-Develop Phase {N}

### Selected Issues ({count} issues, {team_count} teams)

| Team | Issues | Description |
|------|--------|-------------|
| Team 1 | ID, ID | Brief scope |
| Team 2 | ID, ID | Brief scope |

### Merge Order
1. Team N (foundation) → main
2. Team N → main

### Remaining after this phase
- {count} issues still open

Executing...
```

If `--dry-run`: print the plan, then continue to next loop iteration (plan the next phase from projected state) without executing. After all phases planned, print full sequence and STOP.

## Step 3: Execute via /team-develop

Invoke `/team-develop` with these parameters:
- `--teams={teams}` from the plan
- `--strategy=staggered`
- `--merge=rebase`
- `--build-gate=true`
- `--scope=custom` with the specific issue IDs selected

Pass full issue context to each team (descriptions, files, patterns).

This runs the full `/team-develop` lifecycle:
- Phase 0: Permissions preflight (first phase only — skip on subsequent phases)
- Phase 1: Plan & Setup (worktrees, branches)
- Phase 2: Execute (parallel teams with reviewers)
- Phase 3: Merge Protocol (sequential rebase)
- Phase 4: Cleanup (worktrees, branches, bd close)

## Step 4: Verify Phase

After `/team-develop` completes:

1. **Build gate on main**:
   ```bash
   pnpm typecheck && pnpm build
   ```
   If this fails:
   - First failure: attempt to fix on main, re-verify
   - Second failure: if `--pause-on-failure`, STOP. Otherwise, revert phase commits (`git reset --hard` to pre-phase commit), log the failure, and continue to next phase with those issues still open.

2. **Issue verification** — for each closed issue, verify:
   - Files mentioned in the issue exist and are implemented (not stubs)
   - Exports are wired up
   - Tests exist if specified in the issue

3. **Log results**:
   ```
   ## Phase {N} Complete

   ### Closed
   - ID: title (VERIFIED)
   - ID: title (VERIFIED)

   ### Issues Found
   - ID: title — missing export (FIXED)

   ### Build: PASSING
   ### Remaining open: {count}
   ```

## Step 5: Compact and Continue

**Mandatory context compaction** between phases. This is critical — without it, context accumulates and quality degrades.

After compaction, re-read essential state:
```bash
bd ready
bd list --all
git log --oneline -10
git status
```

Then return to the top of the loop.

---

## Stop Conditions

The loop terminates when ANY of these are true:

| Condition | Message |
|-----------|---------|
| `bd ready` returns no issues | "All work complete" |
| `phase_number > max_phases` | "Max phases reached ({N}/{max}). Run again to continue." |
| Same issues ready as last phase | "Stuck: no progress. Issues {IDs} remain ready but were not resolved. Investigate manually." |
| Build fails twice in one phase | "Build broken. Phase reverted. Investigate: {error}" |
| `--pause-on-failure` and any failure | "Paused on failure: {details}" |

## Final Report

When the loop terminates, print a summary:

```
## Auto-Develop Complete

### Phases Executed: {N}
### Stop Reason: {reason}

### Issues Closed This Run
| Issue | Title | Phase |
|-------|-------|-------|
| ID | title | 1 |
| ID | title | 2 |

### Issues Still Open
| Issue | Title | Status | Blocked By |
|-------|-------|--------|------------|
| ID | title | open | ID |

### Commits Added
- {hash} {message}
- {hash} {message}

### Total Duration: ~{estimate based on phase count}
```

---

## Error Recovery

| Error | Action |
|-------|--------|
| Team agent fails | `/team-develop` handles internally (retry, then escalate) |
| Merge conflict | `/team-develop` handles (lead resolves) |
| Build fails once | Fix on main and continue |
| Build fails twice | Revert phase, skip those issues, continue |
| Stuck (no progress) | Stop and report — likely a dependency or spec issue |
| Context too large | Compaction between phases prevents this |
| Worktree left behind | Clean up stale worktrees at phase start: `git worktree list` and remove any not in use |

## Stale Worktree Cleanup (each phase start)

Before creating new worktrees, clean up any orphans:
```bash
git worktree list
# For any worktree not matching an active team, remove it:
git worktree remove <path> --force
```

---

## Usage Examples

```bash
# Run up to 5 phases of P1+P2 work with 2 teams
/auto-develop

# Run 3 phases of P1-only work
/auto-develop --max-phases=3 --scope=p1

# Dry run — see what phases would look like
/auto-develop --dry-run

# Conservative — stop on any failure
/auto-develop --pause-on-failure --teams=1

# Aggressive — all priorities, 3 teams, 10 phases
/auto-develop --scope=all --teams=3 --max-phases=10
```
