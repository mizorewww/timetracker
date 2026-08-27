# Versioning

The app version is intentionally handled by the repository instead of memory in a chat thread.

## User-Facing Version

`MARKETING_VERSION` is the version shown in Settings > About. `CURRENT_PROJECT_VERSION` is the build number.

Versions no longer advance on every commit. Bump manually before a release (or whenever a distinct build number is needed):

```sh
make bump-version
```

This increments the patch component of `MARKETING_VERSION` by `0.0.1` and `CURRENT_PROJECT_VERSION` by `1` across all targets in `timetracker.xcodeproj/project.pbxproj`:

```text
1.0.1 (88) -> 1.0.2 (89)
```

Commit the bumped project file together with the release change. To bump by more than a patch (e.g. a minor or major release), edit the `MARKETING_VERSION` fields in `timetracker.xcodeproj/project.pbxproj` directly and keep them identical across all targets.

## Local Git Hook

The repository includes `.githooks/pre-commit`, which runs only the localization parity gate (`scripts/localization_check.sh --quiet`): every commit must keep `.strings` keys identical across `en`, `zh-Hans`, and `zh-Hant`. It no longer touches version fields. Install it once per clone:

```sh
make install-hooks
```

Git intentionally does not activate hooks from tracked files after a clone. The installer sets this clone's local `core.hooksPath` to `.githooks` and verifies that the executable pre-commit hook resolves correctly. Check an existing clone without changing it with:

```sh
make check-hooks
```

## Build Metadata

The app target has a build phase that runs `scripts/write_build_info_plist.sh` (a thin wrapper around the `timetracker_tools.write_build_info_plist` Python module). It writes `AppBuildInfo.plist` into the built app bundle with:

- Git branch
- Short and full commit hash
- Dirty working-tree flag
- UTC build date

Settings > About reads that plist at runtime.
