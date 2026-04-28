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

The repository includes `.githooks/pre-commit`. Enable it once per clone:

```sh
git config core.hooksPath .githooks
```

The hook runs `scripts/bump_marketing_version.sh`, stages `timetracker.xcodeproj/project.pbxproj`, and then lets the commit continue.

Use this only for emergency commits where a version bump is not wanted:

```sh
SKIP_VERSION_BUMP=1 git commit -m "Commit message"
```

## Build Metadata

The app target has a build phase that runs `scripts/write_build_info_plist.sh`. It writes `AppBuildInfo.plist` into the built app bundle with:

- Git branch
- Short and full commit hash
- Dirty working-tree flag
- UTC build date

Settings > About reads that plist at runtime.
