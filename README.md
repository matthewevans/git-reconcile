# git-reconcile

Reconcile a local Git branch with its upstream after pull requests have landed
there, including pull requests merged with GitHub's squash workflow.

`git reconcile` classifies each local commit as either:

- **MERGED** — represented upstream by patch equivalence, a GitHub squash
  commit subject, or a subject listed in a GitHub squash commit body.
- **KEEP** — not represented upstream and therefore replayed on top of the
  current upstream tip.

The dry run is the default. Applying the plan uses `git reset --keep` followed
by `git cherry-pick` rather than a stash/rebase/pop sequence.

## Requirements

- Git
- Bash 4 or newer

macOS ships Bash 3.2. Install a current Bash with Homebrew before using the
tool:

```sh
brew install bash
```

## Install

### From a clone

```sh
git clone https://github.com/<owner>/git-reconcile.git
cd git-reconcile
./install.sh
```

The installer places `git-reconcile` in `$HOME/.local/bin` by default. Add
that directory to `PATH` if needed:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Git discovers executables named `git-<command>` on `PATH`, so no Git alias
is required.

Use `git reconcile -h` for help. Git reserves `git <command> --help` for
manual-page lookup; `git-reconcile --help` also works when invoking the
executable directly.

### Homebrew

After a release and tap are available:

```sh
brew install <owner>/tap/git-reconcile
```

## Usage

```sh
# Inspect the reconciliation plan. Makes no changes.
git reconcile [<upstream>]

# Reset to upstream and replay only commits that still need to be applied.
git reconcile --apply [<upstream>]

# Fetch and prune the remote that owns upstream, then apply the plan.
git reconcile --pull [<upstream>]

# Abort a survivor cherry-pick that paused on a conflict.
git reconcile --abort
```

The default upstream is the current branch's configured upstream. If none is
configured, it is `origin/main`.

## Safety model

- A dry run prints the exact `git reset --keep … && git cherry-pick …` command
  it would use.
- `--apply` refuses to start during a merge, rebase, revert, cherry-pick, or
  unresolved index conflict.
- Local merge commits are rejected because they cannot be replayed safely by
  `git cherry-pick`.
- An untracked path that upstream would create is rejected rather than
  overwritten.
- Uncommitted tracked work is carried forward when possible. If a dirty file
  also changed upstream, the tool snapshots the tracked work, reconciles the
  branch, and replays it with a 3-way merge.
- If a survivor commit conflicts, resolve it and run
  `git cherry-pick --continue`, or restore the prior tip with
  `git reconcile --abort`.

GitHub squash provenance intentionally uses exact, case-sensitive commit
subjects. This reduces false positives, but generic duplicate subjects can
still be ambiguous. Always review the dry-run table before applying it.

## Development

```sh
make lint
make test
```

The integration suite covers patch-id detection, GitHub squash provenance,
applying a reconciliation with tracked work in progress, conflict abort, and
fetch-before-apply behavior.

## License

MIT. See [LICENSE](LICENSE).
