#!/usr/bin/env bash
set -euo pipefail

if ((BASH_VERSINFO[0] < 4)); then
  echo "tests need bash >= 4; found $BASH_VERSION" >&2
  exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tool="$repo_root/bin/git-reconcile"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/git-reconcile.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local actual=$1
  local expected=$2
  local message=$3
  [ "$actual" = "$expected" ] || fail "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local message=$3
  [[ "$haystack" == *"$needle"* ]] || fail "$message: missing '$needle'"
}

setup_repo() {
  local repo=$1
  git init -q -b main "$repo"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config commit.gpgSign false
  printf 'base\n' > "$repo/file.txt"
  printf 'wip base\n' > "$repo/wip.txt"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "base"
}

test_help_and_version() {
  assert_eq "$("$tool" --version)" "git-reconcile 0.1.0" "version"
  assert_contains "$("$tool" --help)" "git reconcile --apply" "help"
}

test_rejects_extra_arguments() {
  local repo="$tmpdir/extra-arguments"
  local output
  setup_repo "$repo"

  if output="$(cd "$repo" && "$tool" main extra 2>&1)"; then
    fail "extra upstream arguments should be rejected"
  fi
  assert_contains "$output" "expected at most one upstream argument" "argument validation"
}

test_install_exposes_git_subcommand() {
  local prefix="$tmpdir/install-prefix"
  local output
  PREFIX="$prefix" "$repo_root/install.sh" >/dev/null
  output="$(PATH="$prefix/bin:$PATH" git reconcile -h)"
  assert_contains "$output" "git reconcile --apply" "installed Git subcommand"
}

test_patch_id_dry_run() {
  local repo="$tmpdir/patch-id"
  local sha
  local output
  setup_repo "$repo"

  git -C "$repo" switch -q -c topic
  printf 'topic\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "add feature"
  sha="$(git -C "$repo" rev-parse HEAD)"

  git -C "$repo" switch -q main
  printf 'upstream preparation\n' > "$repo/upstream.txt"
  git -C "$repo" add upstream.txt
  git -C "$repo" commit -q -m "upstream preparation"
  git -C "$repo" cherry-pick "$sha" >/dev/null
  git -C "$repo" switch -q topic

  output="$(cd "$repo" && "$tool" main 2>&1)"
  assert_contains "$output" "MERGED (patch-id)" "patch-id classification"
  assert_contains "$output" "git reset --keep main" "patch-id plan"
}

test_squash_subject_dry_run() {
  local repo="$tmpdir/squash-subject"
  local output
  setup_repo "$repo"

  git -C "$repo" switch -q -c topic
  printf 'topic\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "Add widget"

  git -C "$repo" switch -q main
  printf 'upstream\n' > "$repo/release.txt"
  git -C "$repo" add release.txt
  git -C "$repo" commit -q -m "Add widget (#123)"
  git -C "$repo" switch -q topic

  output="$(cd "$repo" && "$tool" main 2>&1)"
  assert_contains "$output" "MERGED (squash #)" "squash-subject classification"
}

test_squash_body_dry_run() {
  local repo="$tmpdir/squash-body"
  local output
  setup_repo "$repo"

  git -C "$repo" switch -q -c topic
  printf 'topic\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "add widget tests"

  git -C "$repo" switch -q main
  printf 'upstream\n' > "$repo/release.txt"
  git -C "$repo" add release.txt
  git -C "$repo" commit -q -m "Widget feature (#124)" -m "* add widget tests"
  git -C "$repo" switch -q topic

  output="$(cd "$repo" && "$tool" main 2>&1)"
  assert_contains "$output" "MERGED (squash)" "squash-body classification"
}

test_apply_carries_unrelated_tracked_wip() {
  local repo="$tmpdir/apply-wip"
  setup_repo "$repo"

  git -C "$repo" switch -q -c topic
  printf 'feature\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "add feature"

  git -C "$repo" switch -q main
  printf 'upstream\n' > "$repo/upstream.txt"
  git -C "$repo" add upstream.txt
  git -C "$repo" commit -q -m "upstream change"
  git -C "$repo" switch -q topic
  printf 'wip\n' >> "$repo/wip.txt"

  (cd "$repo" && "$tool" --apply main >/dev/null)

  git -C "$repo" merge-base --is-ancestor main HEAD || fail "upstream should be an ancestor"
  [ -f "$repo/feature.txt" ] || fail "surviving commit should be replayed"
  [ -f "$repo/upstream.txt" ] || fail "upstream change should be present"
  assert_contains "$(git -C "$repo" diff -- wip.txt)" "+wip" "tracked WIP should remain"
}

test_apply_three_way_carries_overlapping_file_wip() {
  local repo="$tmpdir/apply-overlap-wip"
  setup_repo "$repo"

  printf 'base one\nshared 1\nshared 2\nshared 3\nshared 4\nshared 5\nshared 6\nbase two\n' > "$repo/wip.txt"
  git -C "$repo" add wip.txt
  git -C "$repo" commit -q -m "prepare WIP fixture"

  git -C "$repo" switch -q -c topic
  printf 'feature\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "add feature"

  git -C "$repo" switch -q main
  printf 'main one\nshared 1\nshared 2\nshared 3\nshared 4\nshared 5\nshared 6\nbase two\n' > "$repo/wip.txt"
  git -C "$repo" add wip.txt
  git -C "$repo" commit -q -m "upstream WIP-file change"
  git -C "$repo" switch -q topic
  printf 'base one\nshared 1\nshared 2\nshared 3\nshared 4\nshared 5\nshared 6\ntopic two\n' > "$repo/wip.txt"

  (cd "$repo" && "$tool" --apply main >/dev/null)

  assert_eq "$(cat "$repo/wip.txt")" $'main one\nshared 1\nshared 2\nshared 3\nshared 4\nshared 5\nshared 6\ntopic two' "3-way WIP merge"
  [ -f "$repo/feature.txt" ] || fail "surviving commit should be replayed after 3-way WIP merge"
}

test_rejects_untracked_upstream_collision() {
  local repo="$tmpdir/untracked-collision"
  local original
  local output
  setup_repo "$repo"

  git -C "$repo" switch -q -c topic
  printf 'feature\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "add feature"
  original="$(git -C "$repo" rev-parse HEAD)"

  git -C "$repo" switch -q main
  printf 'upstream\n' > "$repo/collision.txt"
  git -C "$repo" add collision.txt
  git -C "$repo" commit -q -m "upstream collision"
  git -C "$repo" switch -q topic
  printf 'local\n' > "$repo/collision.txt"

  if output="$(cd "$repo" && "$tool" --apply main 2>&1)"; then
    fail "untracked collision should be rejected"
  fi
  assert_contains "$output" "untracked locally but added by main" "untracked collision diagnostic"
  assert_eq "$(git -C "$repo" rev-parse HEAD)" "$original" "untracked collision should not move HEAD"
  assert_eq "$(cat "$repo/collision.txt")" "local" "untracked collision should preserve local file"
}

test_abort_restores_original_head() {
  local repo="$tmpdir/abort"
  local original
  setup_repo "$repo"

  git -C "$repo" switch -q -c topic
  printf 'topic\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "topic change"
  original="$(git -C "$repo" rev-parse HEAD)"

  git -C "$repo" switch -q main
  printf 'main\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "main change"
  git -C "$repo" switch -q topic

  if (cd "$repo" && "$tool" --apply main >/dev/null 2>&1); then
    fail "conflicting reconciliation should pause"
  fi
  git -C "$repo" rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null || fail "cherry-pick should be paused"

  (cd "$repo" && "$tool" --abort >/dev/null)
  assert_eq "$(git -C "$repo" rev-parse HEAD)" "$original" "abort should restore original HEAD"
}

test_pull_fetches_then_applies() {
  local repo="$tmpdir/pull-work"
  local remote="$tmpdir/pull-remote.git"
  local publisher="$tmpdir/publisher"
  setup_repo "$repo"
  git init -q --bare "$remote"
  git -C "$remote" symbolic-ref HEAD refs/heads/main
  git -C "$repo" remote add upstream "$remote"
  git -C "$repo" push -q -u upstream main

  git -C "$repo" switch -q -c topic
  printf 'feature\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "add feature"
  git -C "$repo" branch --set-upstream-to=upstream/main topic

  git clone -q "$remote" "$publisher"
  git -C "$publisher" config user.name "Test User"
  git -C "$publisher" config user.email "test@example.com"
  git -C "$publisher" config commit.gpgSign false
  printf 'upstream\n' > "$publisher/upstream.txt"
  git -C "$publisher" add upstream.txt
  git -C "$publisher" commit -q -m "upstream change"
  git -C "$publisher" push -q origin main
  git -C "$repo" update-ref -d refs/remotes/upstream/main

  (cd "$repo" && "$tool" --pull >/dev/null)

  git -C "$repo" merge-base --is-ancestor upstream/main HEAD || fail "--pull should fetch current upstream"
  [ -f "$repo/feature.txt" ] || fail "--pull should replay surviving commits"
  [ -f "$repo/upstream.txt" ] || fail "--pull should include fetched upstream changes"
}

test_pull_applies_local_tracking_upstream() {
  local repo="$tmpdir/local-tracking"
  setup_repo "$repo"

  git -C "$repo" switch -q -c topic
  printf 'feature\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "add feature"

  git -C "$repo" switch -q main
  printf 'upstream\n' > "$repo/upstream.txt"
  git -C "$repo" add upstream.txt
  git -C "$repo" commit -q -m "upstream change"
  git -C "$repo" switch -q topic
  git -C "$repo" branch --set-upstream-to=main topic

  (cd "$repo" && "$tool" --pull >/dev/null)

  git -C "$repo" merge-base --is-ancestor main HEAD || fail "local upstream should be an ancestor"
  [ -f "$repo/feature.txt" ] || fail "local tracking --pull should replay surviving commits"
  [ -f "$repo/upstream.txt" ] || fail "local tracking --pull should include upstream changes"
}

test_help_and_version
test_rejects_extra_arguments
test_install_exposes_git_subcommand
test_patch_id_dry_run
test_squash_subject_dry_run
test_squash_body_dry_run
test_apply_carries_unrelated_tracked_wip
test_apply_three_way_carries_overlapping_file_wip
test_rejects_untracked_upstream_collision
test_abort_restores_original_head
test_pull_fetches_then_applies
test_pull_applies_local_tracking_upstream

echo "ok - git-reconcile integration tests"
