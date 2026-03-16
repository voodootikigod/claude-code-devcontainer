# Next Phase

Automated phase planner and executor for Skills Trace. Reviews remaining beads issues, plans optimal team assignments, executes parallel development via `/team-develop`, and verifies all merged work.

## Arguments

- `$ARGUMENTS` — Optional: specific issue IDs, priority filter (e.g., "P2 only"), or phase name (e.g., "Phase 6"). Defaults to all ready P1-P3 issues.

---

## Step 1: Review Remaining Work

Run these commands to understand the current state:

```bash
bd ready
bd list --all
```

From the output:
1. Identify all **open** issues grouped by epic/phase
2. Note which epics have all subtasks closed (close those epics first with `bd close`)
3. Map the dependency graph — which issues block others
4. Filter by `$ARGUMENTS` if provided (e.g., specific priority or phase)

## Step 2: Evaluate and Plan

Analyze the open issues and determine:

### Issue Selection
- Select issues that are **ready** (unblocked) and match the scope
- Prioritize by: P1 > P2 > P3 (skip P4 backlog unless explicitly requested)
- Respect dependencies — don't schedule blocked issues
- Cap at 6-9 issues per phase (2-3 per team, 3 teams max)

### Team Assignment Strategy
Group issues into teams based on these rules:

| Grouping Principle | Rationale |
|-------------------|-----------|
| Same package/directory | Minimizes merge conflicts |
| Related functionality | Shared context reduces ramp-up |
| Independent file sets | Enables true parallel work |
| Balanced workload | Similar complexity per team |

### Team Sizing
- **1 team**: 1-2 issues, all in same area
- **2 teams**: 3-4 issues, two distinct areas
- **3 teams**: 5-9 issues, three distinct areas (preferred max)

### Merge Order
Plan the merge sequence based on:
1. Foundation/shared code first (types, schemas, core packages)
2. Packages before apps (core before express/vercel before web)
3. Independent changes can merge in any order

## Step 3: Present Plan and Get Approval

Before executing, present to the user:

```
## Next Phase Plan

### Selected Issues (N issues across M teams)

| Team | Worktree | Issues | Description |
|------|----------|--------|-------------|
| Team 1 | worktree-team-1 | t0z.X.Y, t0z.X.Z | Brief scope |
| Team 2 | worktree-team-2 | t0z.A.B, t0z.A.C | Brief scope |
| Team 3 | worktree-team-3 | t0z.D.E, t0z.D.F | Brief scope |

### Merge Order
1. Team N (foundation) → main
2. Team N (depends on above) → main
3. Team N (independent) → main

### Deferred to Next Phase
- List remaining issues not included

Proceed? (Y/n)
```

Wait for user confirmation before proceeding.

## Step 4: Execute Team Develop

Invoke the `/team-develop` command with the planned parameters. Construct a detailed prompt that includes:

For **each team**:
- The beads issue IDs and titles
- Full issue descriptions (from `bd show <id>`)
- Specific files to create/modify
- Technical requirements from the issue description
- Relevant existing code patterns to follow
- Build and test commands specific to their workspace

Include these instructions for all teams:
- Run `pnpm run fix` before committing
- Follow code standards from CLAUDE.md (no console.log, no any types, async/await, const over let)
- Use bd to claim issues at start
- Commit with descriptive messages, do NOT push or merge

### Monitoring
As teams complete:
- Track which teams are done
- Note any failures or issues

## Step 5: Merge Protocol

After all teams complete, merge in the planned order:

For each team (in dependency order):
1. Verify worktree is clean: `git status` in worktree
2. Rebase onto main: `git rebase main` in worktree
3. If rebase fails due to worktree issues, use `git cherry-pick` as fallback
4. Fast-forward main: `git merge --ff-only <branch>`
5. Build gate: Run `npx tsup` and/or `npx vitest run` for affected packages
6. If build fails, investigate and fix before proceeding

After all merges:
- Reinstall deps if package.json changed: `pnpm install`
- Run full test suite to verify no regressions

## Step 6: Verification

For **each closed issue**, launch a parallel verification agent that:

1. Reads the issue description (`bd show <id>`) to understand requirements
2. Checks that all specified files exist on main and are fully implemented (not stubs)
3. Verifies key functionality matches the issue spec:
   - Classes/functions mentioned in description exist with correct signatures
   - Tests exist and cover the described scenarios
   - Exports are properly wired up in index.ts / package.json
   - Configuration changes (env vars, CI files, etc.) are present
4. Reports findings per issue: VERIFIED or ISSUES FOUND with details

Run all verification agents in parallel for speed.

Present consolidated results:

```
## Verification Results

| Issue | Title | Status | Notes |
|-------|-------|--------|-------|
| t0z.X.Y | Title | VERIFIED | All requirements met |
| t0z.X.Z | Title | ISSUE | Missing export in index.ts |
```

If any issues are found:
- Fix them directly on main
- Commit with message: `fix: address verification issues from phase N`
- Re-verify the fixes

## Step 7: Cleanup

1. Close all implemented issues: `bd close <id> --reason "..."`
2. Remove worktrees: `git worktree remove <path>`
3. Delete team branches: `git branch -d <branch>` (use `-D` if cherry-picked)
4. Update CLAUDE.md and README.md if the implemented features change the project structure
5. Commit doc updates if needed
6. Report final status:

```
## Phase Complete

### Commits Added
- list of commits

### Issues Closed
- list with reasons

### Remaining Open Work
- list of what's left for next phase

### Test Results
- X tests passing across Y test files
```
