---
name: repo-workflow
description: Touch Jockey's folder layout, worktrees, branches, commits and pushing to GitHub. Use when starting parallel work, creating a worktree, merging a branch, committing or pushing.
---

# Touch Jockey repository workflow

## Folders

- `~/code/touch-jockey/dev` is the main checkout (branch `main`). The user runs the
  app built from here.
- **Worktrees** for parallel work go in **sibling folders** under `~/code/touch-jockey/`,
  for example `git worktree add ../mixer -b mixer-controls`.
- `~/code/touch-jockey/branding` holds names and icons. The official icon is
  `svg/tj-a-monogram.svg`, the TJ ligature.

## Remote

- The remote is GitHub `juuxstar/touch-jockey`, a private repo on the user's
  personal account. Commits are authored as the personal identity
  (`juuxstar@gmail.com`) that the repo is configured with.
- **Commit and push only when the user asks.** Merging a finished feature branch
  into `main` also needs the user's go-ahead.

## Commits

- Commit in small, logical units. The first line summarises; the body lists
  user-visible changes.
- End the message with a `Co-Authored-By:` line for the model that helped.

## Parallel agents and merging

- Give each background agent its own worktree and branch, and tell it not to touch
  `dev` or the other worktrees, and not to launch the app (ports 8080/8081).
- If `main` has uncommitted work an agent needs, copy it into the worktree as the
  branch's first commit. Don't commit it to `main` without asking.
- When two branches both carry the same base work, merges conflict where a branch
  also edited those lines. If the branch's base equals `main` (check with
  `git diff <main-commit> <branch-base>`), the branch side is a superset and you can
  take it. Otherwise resolve by hand and rebuild.
- After merging: build, run the engine tests, relaunch the user's app, and report
  what wasn't verified.
