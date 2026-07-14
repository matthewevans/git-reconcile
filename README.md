# git-reconcile

[![CI](https://github.com/matthewevans/git-reconcile/actions/workflows/ci.yml/badge.svg)](https://github.com/matthewevans/git-reconcile/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A Git subcommand that brings a local branch up to date with its upstream after
some of its commits have already landed there. It alleviates two problems that
make plain `git rebase` painful in that situation:

- **Diverged squash merges.** If a commit was modified after it left your
  branch — say, a fixup made in a shipping worktree and pushed back before the
  PR was squash-merged — the squash commit no longer patch-matches your local
  commit. `git rebase` replays the stale commit and conflicts. `git reconcile`
  recognizes it as already merged from the squash commit's provenance (its
  `(#123)` subject and `* subject` body bullets) and drops it.
- **Dirty working trees.** `git rebase` makes you stash uncommitted changes
  first. `git reconcile` carries tracked work forward in place, falling back
  to a 3-way merge only for files that also changed upstream.

`git reconcile` classifies every local commit as already **MERGED** upstream or
a survivor to **KEEP**, then rebuilds the branch on the upstream tip replaying
only the survivors:

```console
$ git reconcile
MERGED (patch-id) 9e1a4c2b10  add parser
MERGED (squash)   6f7a8b9c0d  add parser tests
KEEP              abcdef1234  clarify error

git reset --keep origin/main && git cherry-pick abcdef1234
```

The dry run above is the default and makes no changes; `--apply` executes the
printed plan.

## Installation

### Homebrew

```sh
brew install matthewevans/tap/git-reconcile
```

### From source

```sh
git clone https://github.com/matthewevans/git-reconcile.git
cd git-reconcile
./install.sh          # installs to ~/.local/bin (override with PREFIX=/usr/local)
```

Make sure the install directory is on `PATH`; Git then picks up the
`git-reconcile` executable as the `git reconcile` subcommand automatically:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

### Requirements

- Git
- Bash 4 or newer — macOS ships Bash 3.2, so `brew install bash` first
  (the Homebrew package handles this for you)

## Usage

```sh
git reconcile [<upstream>]           # Dry run (default): print the plan, change nothing
git reconcile --apply [<upstream>]   # Rebuild the branch on upstream, replaying survivors
git reconcile --pull [<upstream>]    # Fetch + prune the upstream remote, then --apply
git reconcile --abort                # Bail out of a reconciliation paused on a conflict
git reconcile -h                     # Help (git reserves `--help` for man pages)
```

`<upstream>` defaults to the current branch's configured upstream, falling
back to `origin/main`.

### Using a fork

On a fork, `origin` normally points to your fork rather than the canonical
repository. Add the canonical repository as `upstream` once, then name its
default branch explicitly:

```sh
git remote add upstream https://github.com/OWNER/PROJECT.git
git reconcile --pull upstream/main
```

`--pull` fetches the remote named by its argument before reconciling, so the
second command needs no separate `git fetch`. A bare `git reconcile --pull`
is appropriate only when your branch already tracks `upstream/main`; a typical
fork branch tracks `origin/<branch>` and would otherwise compare against the
fork instead of the canonical project.

## How it works

A local commit (in `<upstream>..HEAD`) counts as **MERGED** when either:

- **Patch-id equivalence** — its diff matches an upstream commit
  (`git cherry`), which covers clean merges, cherry-picks, and rebases.
- **GitHub squash provenance** — its subject appears in an upstream squash
  commit, either as the squash subject itself (`add parser (#42)`) or as a
  `* subject` bullet in the squash commit body. This catches commits whose
  content diverged before the squash landed (e.g. a fixup made in another
  worktree or on the PR branch), where patch-id matching fails.

Everything else is a **KEEP** survivor. Applying the plan runs
`git reset --keep <upstream>` followed by `git cherry-pick <survivors>`.

## Examples

### Continue a branch after its PR was squash-merged

Your branch had `add parser` (A) and `add parser tests` (B). During review a
fixup was pushed from another worktree, then the PR was squash-merged as S.
Meanwhile you kept working and committed `clarify error` (C):

```text
      A---B---C     topic
     /
    M---------S     origin/main    S = "Add parser (#42)" = A + B + fixup
```

Because of the fixup, A and B no longer patch-match S, so
`git rebase origin/main` would replay them onto S and conflict. The squash
commit still names them in its body:

```text
Add parser (#42)

* add parser
* add parser tests
```

so `git reconcile` classifies them as merged and replays only the survivor:

```console
$ git reconcile --apply
MERGED (squash)   1a2b3c4d5e  add parser
MERGED (squash)   6f7a8b9c0d  add parser tests
KEEP              abcdef1234  clarify error

git-reconcile: reconciled onto origin/main (1 commit(s) replayed). Prev HEAD 3c9d1e07aa.
```

```text
              C'    topic
             /
    M-------S       origin/main
```

### Fetch and reconcile while keeping work in progress

`--pull` fetches the upstream remote, then applies the plan, with no stash
step. Say you have an uncommitted edit to `docs.md`, your one commit A was
squash-merged as S, and upstream has since gained T:

```text
    working tree: docs.md modified (uncommitted)

      A             topic
     /
    M---S---T       origin/main    S = "add parser (#7)" = A
```

```console
$ git reconcile --pull
MERGED (squash #) 1a2b3c4d5e  add parser

git-reconcile: reconciled onto origin/main (0 commit(s) replayed). Prev HEAD 3c9d1e07aa.
```

```text
    working tree: docs.md still modified — never stashed

            topic
            v
    M---S---T       origin/main
```

If T had also touched `docs.md`, the edit would be replayed with a 3-way
merge, leaving only genuinely overlapping lines for manual resolution.

### Resolve or abort a conflicting survivor

A survivor commit can genuinely conflict with upstream. `--apply` then pauses
at a standard cherry-pick conflict:

```sh
# Fix the conflict markers, then:
git add <resolved files>
git cherry-pick --continue

# Or discard the partial reconciliation and restore the original branch tip:
git reconcile --abort
```

## Safety model

- The dry run is the default and prints the exact command `--apply` would run.
- `--apply` refuses to start during a merge, rebase, revert, cherry-pick, or
  with unresolved index conflicts, and rejects local merge commits (they
  cannot be replayed by `git cherry-pick`).
- Untracked files that upstream would overwrite are detected and block the
  run rather than being clobbered.
- Uncommitted tracked work survives: `git reset --keep` carries unrelated
  changes forward, and overlapping files are replayed with a 3-way merge.
- On failure, the tool restores the original branch tip and working tree;
  `git reconcile --abort` recovers from a paused conflict.

Squash provenance matches commit subjects exactly and case-sensitively to
minimize false positives, but generic duplicate subjects can still be
ambiguous — review the dry-run table before applying.

## Development

```sh
make lint   # bash -n syntax checks
make test   # integration suite against throwaway repos
```

## License

[MIT](LICENSE)
