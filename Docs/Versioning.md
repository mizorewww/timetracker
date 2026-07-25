# Versioning

The app version is intentionally handled by the repository instead of memory in a chat thread.

## User-Facing Version

`MARKETING_VERSION` is the version shown in Settings > About. Every normal `git commit` should increase the patch component by `0.0.1`.

Example:

```text
1.0.1 -> 1.0.2
```

`CURRENT_PROJECT_VERSION` is the build number. It increments by `1` at the same time.

## Local Git Hook

The repository includes `.githooks/pre-commit`. Install it once per clone:

```sh
make install-hooks
```

Git intentionally does not activate hooks from tracked files after a clone. The installer sets this clone's local `core.hooksPath` to `.githooks` and verifies that the executable pre-commit hook resolves correctly. Check an existing clone without changing it with:

```sh
make check-hooks
```

The hook runs `scripts/stage_commit_version.sh` (a thin wrapper around the `timetracker_tools.stage_commit_version` Python module; see [DevelopmentTools](DevelopmentTools.md)). It derives the next version from `HEAD`, so repeating a failed commit attempt is idempotent. It updates only the version fields in the index and working copy: already staged project changes stay staged, while unrelated unstaged project changes remain unstaged.

Run the isolated Git integration test with:

```sh
make test-versioning
```

Every `git commit`, including `--allow-empty` and `--amend`, advances the version. The standard Git `--no-verify` escape can bypass client-side hooks, so release verification must still confirm the installed bundle version.

## Build Metadata

The app target has a build phase that runs `scripts/write_build_info_plist.sh` (a thin wrapper around the `timetracker_tools.write_build_info_plist` Python module). It writes `AppBuildInfo.plist` into the built app bundle with:

- Git branch
- Short and full commit hash
- Dirty working-tree flag
- UTC build date

Settings > About reads that plist at runtime.
