#!/usr/bin/env python3
"""归档 iOS 与 macOS Release 产物,导出开发签名 IPA,复制并签名校验 macOS .app,再生成 macOS zip。

默认产物位于 build/Archives/<timestamp> 与 build/Exports/<timestamp>,
build/Exports/latest 指向最近一次导出。同秒重复执行自动追加 -1/-2 后缀。
"""

from __future__ import annotations

import os
import shutil
from datetime import datetime
from pathlib import Path

from timetracker_tools.cli_utils import env, run


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    project = env("PROJECT", str(root / "timetracker.xcodeproj"))
    scheme = env("SCHEME", "timetracker")
    configuration = env("CONFIGURATION", "Release")
    team_id = os.environ.get("DEVELOPMENT_TEAM", "LT98S43NKA")
    product_name = env("PRODUCT_NAME", "timetracker")

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    build_root = Path(env("BUILD_ROOT", str(root / "build")))
    derived_data = build_root / "DerivedData"
    export_options = Path(env("IOS_EXPORT_OPTIONS", str(root / "BuildSupport/ExportOptions-iOS-development.plist")))

    if not Path(project).is_dir():
        raise SystemExit(f"Xcode project not found: {project}")
    if not export_options.is_file():
        raise SystemExit(f"iOS export options plist not found: {export_options}")
    if not product_name or "/" in product_name or product_name in (".", ".."):
        raise SystemExit(f"PRODUCT_NAME must be a single app-bundle name: {product_name}")

    archive_root = build_root / "Archives" / timestamp
    export_root = build_root / "Exports" / timestamp
    latest_link = build_root / "Exports" / "latest"

    if latest_link.exists() and not latest_link.is_symlink():
        raise SystemExit(f"Refusing to replace non-symlink latest export path: {latest_link}")

    suffix = 0
    while archive_root.exists() or export_root.exists():
        suffix += 1
        archive_root = build_root / "Archives" / f"{timestamp}-{suffix}"
        export_root = build_root / "Exports" / f"{timestamp}-{suffix}"

    ios_archive = archive_root / f"{product_name}-iOS.xcarchive"
    mac_archive = archive_root / f"{product_name}-macOS.xcarchive"
    ios_export = export_root / "iOS"
    mac_export = export_root / "macOS"

    archive_root.mkdir(parents=True, exist_ok=True)
    ios_export.mkdir(parents=True, exist_ok=True)
    mac_export.mkdir(parents=True, exist_ok=True)
    derived_data.mkdir(parents=True, exist_ok=True)

    print(f"==> Archiving iOS ({configuration}, team {team_id})")
    run([
        "xcodebuild", "-project", project, "-scheme", scheme, "-configuration", configuration,
        "-destination", "generic/platform=iOS", "-archivePath", str(ios_archive),
        "-derivedDataPath", str(derived_data),
        f"DEVELOPMENT_TEAM={team_id}", "CODE_SIGN_STYLE=Automatic",
        "-allowProvisioningUpdates", "archive",
    ], check=True)

    print("==> Exporting IPA")
    run([
        "xcodebuild", "-exportArchive", "-archivePath", str(ios_archive),
        "-exportPath", str(ios_export), "-exportOptionsPlist", str(export_options),
        "-allowProvisioningUpdates",
    ], check=True)

    print(f"==> Archiving macOS ({configuration}, team {team_id})")
    run([
        "xcodebuild", "-project", project, "-scheme", scheme, "-configuration", configuration,
        "-destination", "generic/platform=macOS", "-archivePath", str(mac_archive),
        "-derivedDataPath", str(derived_data),
        f"DEVELOPMENT_TEAM={team_id}", "CODE_SIGN_STYLE=Automatic",
        "-allowProvisioningUpdates", "archive",
    ], check=True)

    mac_app_in_archive = mac_archive / "Products" / "Applications" / f"{product_name}.app"
    mac_app_out = mac_export / f"{product_name}.app"
    mac_zip_out = mac_export / f"{product_name}-macOS-development.zip"

    if not mac_app_in_archive.is_dir():
        raise SystemExit(f"Expected macOS app not found at: {mac_app_in_archive}")

    print("==> Copying signed macOS .app")
    if mac_app_out.exists():
        shutil.rmtree(mac_app_out, ignore_errors=True)
    if mac_zip_out.exists():
        mac_zip_out.unlink()
    run(["ditto", str(mac_app_in_archive), str(mac_app_out)], check=True)
    run(["ditto", "-c", "-k", "--keepParent", str(mac_app_out), str(mac_zip_out)], check=True)

    print("==> Verifying signatures")
    ipa_paths = list(ios_export.glob("*.ipa"))
    if not ipa_paths:
        raise SystemExit(f"IPA export failed: no .ipa file found in {ios_export}")
    ipa_path = ipa_paths[0]
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(mac_app_out)], check=True)

    if latest_link.is_symlink() or latest_link.exists():
        latest_link.unlink()
    latest_link.symlink_to(export_root, target_is_directory=True)

    print(
        f"\nDone.\n"
        f"iOS IPA:       {ipa_path}\n"
        f"macOS app:     {mac_app_out}\n"
        f"macOS zip:     {mac_zip_out}\n"
        f"Archives:      {archive_root}\n"
        f"Latest link:   {latest_link}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())