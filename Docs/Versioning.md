# Versioning

## User-Facing Version

`MARKETING_VERSION` is shown in Settings > About; `CURRENT_PROJECT_VERSION` is the build number. Versions do not advance on every commit — bump manually before a release or when a distinct build number is needed:

```sh
make bump-version
```

This increments the patch component of `MARKETING_VERSION` by `0.0.1` and `CURRENT_PROJECT_VERSION` by `1` across all targets in `timetracker.xcodeproj/project.pbxproj` (`1.0.1 (88)` → `1.0.2 (89)`). Commit the bumped project file with the release change. For a minor/major bump, edit the `MARKETING_VERSION` fields directly and keep them identical across all targets.

## Local Git Hook

`.githooks/pre-commit` runs only the localization parity gate (`scripts/localization_check.sh --quiet`): every commit must keep `.strings` keys identical across `en`, `zh-Hans`, and `zh-Hant`. It does not touch version fields. Install it once per clone (`make install-hooks`) and check it read-only with `make check-hooks`.

## Build Metadata

The app target's `Write Build Info` build phase runs `scripts/write_build_info_plist.sh` (a thin wrapper around the `timetracker_tools.write_build_info_plist` Python module) and writes `AppBuildInfo.plist` into the built bundle with Git branch, short/full commit hash, dirty-worktree flag, and UTC build date. Settings > About reads that plist at runtime; do not hard-code Git metadata in Swift source.
