# Changelog

## 0.2.0 - 2026-07-20

- Reconcile apply now replays survivors and merges tracked WIP in-core before a
  single working-tree materialization pass, avoiding unnecessary file mtime
  churn in large repositories.
- A survivor whose changes are already present upstream is kept as an
  empty-diff commit instead of pausing on cherry-pick's empty-commit prompt.

## 0.1.0 - 2026-07-14

- Initial release of `git reconcile`.
- Detects patch-equivalent and GitHub squash-merge provenance.
- Replays surviving commits while preserving working-tree changes when safe.
