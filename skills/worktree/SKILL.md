---
name: worktree
description: Start, list, and tear down git worktrees for isolated parallel work. Creates a worktree on a task-named branch, bootstraps the gitignored files a fresh checkout lacks, and switches the session into it. Teardown runs a safety sweep (uncommitted work, unpushed commits, PR state) before anything is deleted.
user-invocable: true
---

# Worktree Skill

> **Repo-specific guidance.** If `.llm-academy/worktree.md` exists at the repo root, read it before applying this skill — it overrides the generic guidance below for this project. The shared profile `.llm-academy/repo.md`, if present, applies to all skills and agents.

Git worktrees let one clone have several branches checked out at once, in separate
directories, so parallel work never fights over a single working copy. This skill
covers the whole lifecycle: **start**, **list**, **remove**.

The teardown half is the reason this skill exists. Removing a worktree deletes a
working directory and usually a branch — work that is uncommitted or unpushed is
gone with no undo. Every removal therefore passes a safety sweep first, and
nothing destructive happens without the user seeing exactly what would be lost.

## Usage

```
/worktree                      # infer intent from context; ask if ambiguous
/worktree 42                   # start a worktree for issue #42
/worktree auth-refactor        # start a worktree for a named task
/worktree list                 # status of every worktree
/worktree remove               # tear down (defaults to the current worktree)
/worktree remove issue-42      # tear down a named worktree
```

Natural phrasing routes the same way — "let's start a new worktree" → **start**,
"let's remove and clean up the worktree" → **remove**. When the mode is genuinely
unclear, ask once; do not guess into a destructive path. **Ambiguity always
resolves toward start or list, never toward remove.**

## Conventions

Defaults, all overridable in `.llm-academy/worktree.md`:

| Thing | Default |
|-------|---------|
| Worktree location | `.claude/worktrees/<name>/` |
| Name from an issue | `issue-<number>` |
| Name from a task | short kebab-case slug (≤ 30 chars) |
| Branch from an issue | `feature/issue-<number>` |
| Branch from a task | `feature/<slug>` |
| Base ref | `origin/<default-branch>`, after `git fetch origin` |

**Why `.claude/worktrees/`.** `EnterWorktree` accepts an arbitrary registered path
on first entry from the session's launch directory, but a *worktree-to-worktree*
switch only accepts paths under `.claude/worktrees/` of the same repo. Defaulting
there keeps every switch legal. The branch naming matches `feature-flow`'s
`feature/issue-<number>` so a worktree started here drops straight into that
pipeline.

---

## Mode: start

### Step 1 — Preconditions

1. Confirm this is a git repo (`git rev-parse --git-dir`). If not, stop and say so.
2. Run `git worktree list` and record the topology. The first entry is the **main
   worktree**.
3. If the session is **already inside a secondary worktree**, do not nest a new one
   silently. Say which worktree you're in and offer: switch to a different existing
   worktree, create the new one anyway (it is registered against the same repo, so
   this works), or stop.

### Step 2 — Determine what we're working on

Resolve in this order, and stop at the first that answers:

1. **An argument was given.** A bare number is an issue; anything else is a slug.
2. **The conversation makes it obvious.** If this session has been discussing a
   specific issue, PR, or task, propose it and confirm in one line — "Starting a
   worktree for #42 (notification digest) — right?" Do not re-ask what was just
   established.
3. **Otherwise, ask.** Use **AskUserQuestion** with concrete candidates when there
   are any: recently discussed issues, open issues assigned to the user, or open
   issues in the current milestone (`gh issue list`). Always leave room for a
   free-text answer — the user may be starting something with no issue at all.

If the answer is an issue number, fetch the title (`gh issue view <n>`) to confirm
you have the right one and to name things sensibly. If the answer is prose,
derive the slug yourself and state it; don't make the user invent a directory name.

### Step 3 — Check for collisions

Before creating anything:

- **Worktree path already exists** (in `git worktree list`) → don't create a
  duplicate. Offer to enter the existing one instead (Step 6).
- **Branch already exists** locally or on the remote → do not clobber it. Create
  the worktree *on* that branch: `git worktree add <path> <branch>`, skipping the
  `-b`. Tell the user you attached to the existing branch rather than branching
  fresh, and say whether it is behind the base ref.
- **Path exists on disk but is not a registered worktree** (leftover from a manual
  `rm -rf`) → run `git worktree prune` and re-check before deciding.

### Step 4 — Create it

```bash
git fetch origin
git worktree add .claude/worktrees/<name> -b <branch> origin/<default-branch>
```

Base on `origin/<default-branch>`, not local HEAD — a worktree started from a stale
or dirty local branch inherits that mess. If the user explicitly wants to branch
from current HEAD or another ref, honor it and say what you based on.

Then make sure the worktree directory is ignored, so it never shows up as untracked
in the main worktree:

```bash
git check-ignore -q .claude/worktrees || echo '.claude/worktrees/' >> .gitignore
```

Match the surrounding `.gitignore` style, and mention the edit — it is a tracked
file. If `.claude/` as a whole is already ignored, add nothing.

### Step 5 — Bootstrap the gitignored files

**This is the step that makes the worktree actually usable, and it is easy to
forget.** A new worktree contains only *tracked* files. Everything gitignored is
absent: installed dependencies, local env files, and — in a repo that uses
llm-academy — the `.claude/` skill and agent symlinks. Without this step the new
worktree has no skills installed.

Work through these, from the main worktree as the source:

1. **llm-academy install.** If the main worktree has symlinks under
   `.claude/skills/` or `.claude/agents/`, resolve the clone path from one of them
   (`readlink -f`, then walk up past `skills/<slug>`) and re-run that clone's
   `install.sh` from inside the new worktree with the same selection. If
   `install.sh` isn't reachable, recreate the same symlinks directly.
2. **Local env files.** Copy the gitignored env files the project uses — typically
   `.env`, `.env.local`, and anything the overlay names. **Copy them with `cp`;
   never read, print, or summarize their contents.** If a file looks like it holds
   credentials, copying it is fine — opening it is not.
3. **Dependencies.** Run the project's install command (from
   `.llm-academy/repo.md`, e.g. `npm ci`, `uv sync`, `bundle install`). If it is
   slow or you're unsure it's wanted, report the command and ask rather than
   burning minutes unprompted.
4. **Anything else the overlay lists** — local config, fixture data, build caches
   worth seeding.

Report what you bootstrapped and what you skipped. A skipped step the user didn't
know about is a confusing failure ten minutes later.

### Step 6 — Enter it

```
EnterWorktree({ path: ".claude/worktrees/<name>" })
```

This switches **this session's** working directory into the worktree. Use `path`,
not `name` — the worktree already exists, and `name` would create a second one.

If `EnterWorktree` is unavailable (headless, restricted tools), say so and give the
user the manual incantation instead:

```
cd .claude/worktrees/<name> && claude
```

### Step 7 — Report

```
Worktree: .claude/worktrees/issue-42
Branch:   feature/issue-42  (from origin/main)
Session:  now in the worktree
Bootstrap: .claude/ symlinks re-installed · .env copied · npm ci run
Next:     /feature-flow 42
```

---

## Mode: list

Run `git worktree list --porcelain`, then for each entry report branch, cleanliness
(`git -C <path> status --porcelain`), ahead/behind vs. its upstream
(`git -C <path> rev-list --left-right --count @{u}...HEAD`, tolerating no upstream),
and PR state (`gh pr list --head <branch> --state all --json number,state`).

```
  main       main              clean
  issue-42   feature/issue-42  3 ahead · PR #57 open
  spike-tui  spike/tui         dirty (2 files) · no PR
```

Flag anything that looks abandoned — clean, merged, no unpushed work — as a
removal candidate, but **do not remove it**. Listing is read-only.

---

## Mode: remove

### Step 1 — Identify the target

An argument names it. Otherwise, if the session is inside a secondary worktree,
that's the target — confirm it by name. Otherwise show the list and ask which one.

**Never target the main worktree.** If asked to, refuse and explain: removing it
would take the clone with it.

### Step 2 — Safety sweep (before deleting anything)

Gather all of it before saying a word — a piecemeal interrogation is worse than one
clear picture. Run each against the target path:

| Check | Command |
|-------|---------|
| Uncommitted + untracked | `git -C <path> status --porcelain` |
| Unpushed commits | `git -C <path> log --oneline @{u}..HEAD` — no upstream? compare against the base ref instead: `git -C <path> log --oneline origin/<default-branch>..HEAD` |
| Branch merged | `git -C <path> branch --merged origin/<default-branch>` (fetch first) |
| PR state | `gh pr list --head <branch> --state all --json number,state,url` |
| Stashes | `git -C <path> stash list` |

Two things that trip people up:

- **Stashes are repo-global, not per-worktree.** They survive removal, so they are
  not "lost work" — but a stash created in this worktree becomes very hard to
  place once the branch is gone. Mention any that exist; don't block on them.
- **An open PR means the commits are on the remote**, so deleting the local
  worktree and branch loses nothing. Say that plainly instead of raising alarm.

### Step 3 — Verdict, then act

**Everything is safe** — clean tree, nothing unpushed, and the work is either
merged or on the remote in an open PR. Summarize in one line and proceed to Step 4.
No interrogation needed.

**Work would be lost** — uncommitted changes, untracked files, or unpushed commits.
Stop. Show exactly what is at risk (file counts and names, commit subjects), then
ask via **AskUserQuestion**:

- **Commit and push** — commit the work, push the branch, then remove. If there's no
  PR, offer to open one (`gh pr create`).
- **Open a PR** — for a branch that's already pushed but has no PR.
- **Keep the worktree** — abort the removal, change nothing.
- **Discard it** — delete the work. **Only on explicit confirmation, after the user
  has seen what's being destroyed.** This is the "we decided to toss it" path and it
  is legitimate — just never the default and never inferred.

Do not soften a lossy removal into a safe-sounding one, and do not proceed on
silence. When the user has seen the loss and confirms, proceed without relitigating.

### Step 4 — Handle self-removal

You cannot delete the directory you are standing in — git refuses, and it would
pull the session's cwd out from under it.

If the session is inside the target worktree:

1. If **this session** created it via `EnterWorktree`, call
   `ExitWorktree({ action: "keep" })` — keep, not remove, so the removal stays under
   this skill's control and the safety sweep isn't bypassed.
2. Otherwise, run the removal commands against the main worktree with
   `git -C <main-worktree-path> ...`, which works from anywhere in the repo. Tell
   the user their shell may still be sitting in a deleted directory and to `cd` out.

### Step 5 — Remove and clean up

```bash
git -C <main> worktree remove <path>       # add --force only with explicit consent
git -C <main> worktree prune               # clears stale registrations
git -C <main> branch -d <branch>           # -D only with explicit consent
```

`worktree remove` refuses on a dirty tree and `branch -d` refuses on an unmerged
branch. **Those refusals are the safety net working.** If either fires when the
sweep said things were clean, stop and re-check — something changed, and reaching
for `--force`/`-D` to make the error go away is exactly the wrong move.

**Remote branch.** Delete `origin/<branch>` only when the PR is merged or closed, or
the user explicitly wants the branch gone — and ask first. An open PR whose branch
is deleted closes the PR and loses its commits from the remote.

### Step 6 — Report

```
Removed: .claude/worktrees/issue-42
Branch:  feature/issue-42 deleted (local) · origin/feature/issue-42 kept (PR #57 merged, remote already pruned by GitHub)
Session: back in /home/you/projects/repo
```

---

## Customization Points

Overlay in `.llm-academy/worktree.md`:

- **Worktree location** if not `.claude/worktrees/` (e.g. `.worktrees/`, or a
  sibling directory outside the repo). Note that a location outside
  `.claude/worktrees/` blocks worktree-to-worktree `EnterWorktree` switches.
- **Branch naming** if not `feature/issue-<n>` / `feature/<slug>`.
- **Default branch** if not `main`.
- **Bootstrap steps** — the exact env files to copy, the dependency install
  command, any local config or seeded caches, and whether to run them
  automatically or ask.
- **Whether the repo uses PRs at all** — the removal sweep's PR check is noise in a
  repo that lands directly on the default branch.
- **Removal policy** — e.g. always keep the remote branch, or always prune it once
  the PR is merged.

## Do NOT

- Do **not** remove a worktree without running the full safety sweep first, even if
  the user sounds certain. The sweep is fast; showing the user a clean bill of
  health costs one line.
- Do **not** use `--force` or `branch -D` to silence a refusal. Escalate to the
  user instead.
- Do **not** delete a remote branch with an open PR without explicit confirmation.
- Do **not** read, print, or summarize the contents of env files while bootstrapping
  — copy them and move on.
- Do **not** modify files inside another worktree's tree, or check out a branch
  that is already checked out elsewhere. Both worktrees share one object store; one
  session editing another's checkout is a data-loss bug that looks like a merge
  conflict.
- Do **not** create a worktree from a dirty local HEAD when the user asked for a
  fresh start. Base on `origin/<default-branch>`.
- Do **not** commit the user's work as a side effect of removal unless they chose
  the commit-and-push path.

## When NOT to use this skill

- The user wants a plain branch, not an isolated directory → `git checkout -b`.
- The user is mid-pipeline in `/feature-flow`, which handles its own branch
  creation and is already worktree-aware → let it run.
- The user wants to *switch* to an existing worktree, not create one → that's
  `EnterWorktree({ path })` directly; no skill needed.
