#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
prefix=${PREFIX:-"$HOME/.local"}
bin_dir="$prefix/bin"

install -d "$bin_dir"
install -m 0755 "$script_dir/bin/git-reconcile" "$bin_dir/git-reconcile"

printf '%s\n' "Installed git-reconcile to $bin_dir/git-reconcile"
printf '%s\n' "Ensure $bin_dir is on PATH, then run: git reconcile -h"
