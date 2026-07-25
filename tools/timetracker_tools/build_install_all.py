#!/usr/bin/env python3
"""构建含 Watch 伴侣的 iOS/iPadOS app 与 macOS app,安装到物理 iOS 设备并将 macOS app 复制到 /Applications。

行为等价于原 scripts/build_install_all.sh。iOS 构建会构建依赖型 Watch App 并嵌入,
安装前校验两端 bundle ID、伴侣关系、签名以及开发 profile 是否覆盖当前可见 Apple Watch。
看不到物理 Watch 时仅提示并继续安装 iPhone app。macOS app 经临时目录原子替换 /Applications 下目的 app。
"""

from __future__ import annotations

import json
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

from timetracker_tools.cli_utils import env, run

TRUEISH = {"true", "YES"}
FALSEISH = {"false", "NO"}


def plist_value(plist_path: Path, key: str) -> str | None:
    if not plist_path.exists():
        return None
    with plist_path.open("rb") as handle:
        data = plistlib.load(handle)
    value = data.get(key)
    if value is None:
        return None
    # plistlib decodes plist booleans as Python `bool`, whose str() is
    # capitalized ("True"/"False"). The TRUEISH/FALSEISH sets below use the
    # plist/PlistBuddy convention ("true"/"false", "YES"/"NO"), so normalize
    # booleans to lowercase to keep the shell-script behavior the rewrite was
    # based on. Without this, an embedded Watch app whose
    # WKRunsIndependentlyOfCompanionApp is `false` reads back as "False" and
    # is misclassified as independent, aborting before any device install.
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def require_app_bundle(path: Path, label: str) -> None:
    if not path.is_dir():
        raise SystemExit(f"Expected {label} app bundle was not found: {path}")


def connected_watch_udids(timeout: str) -> list[str]:
    with tempfile.NamedTemporaryFile(prefix="timetracker-watch-devices.", suffix=".json", delete=False) as tmp:
        json_path = Path(tmp.name)
    try:
        result = run(
            ["xcrun", "devicectl", "list", "devices",
             "--filter", "hardwareProperties.platform == 'watchOS' AND hardwareProperties.reality == 'physical'",
             "--timeout", str(timeout), "--json-output", str(json_path)],
            check=False,
            capture_output=True,
        )
        if result.returncode != 0:
            print("Warning: unable to query physical Apple Watch devices.", file=sys.stderr)
            return []
        with json_path.open("rb") as handle:
            payload = json.load(handle)
        udids: list[str] = []
        for device in payload.get("result", {}).get("devices", []):
            udid = device.get("hardwareProperties", {}).get("udid")
            if udid:
                udids.append(udid)
        return udids
    finally:
        try:
            json_path.unlink()
        except OSError:
            pass


def validate_embedded_watch_profile(watch_app: Path, timeout: str) -> None:
    profile_path = watch_app / "embedded.mobileprovision"
    if not profile_path.is_file():
        raise SystemExit("Embedded Watch app has no provisioning profile.")

    decoded = run(["security", "cms", "-D", "-i", str(profile_path)], check=True, capture_output=True).stdout
    try:
        provisioned = plistlib.loads(decoded)
    except plistlib.InvalidFileException as exc:
        raise SystemExit("Unable to read the embedded Watch provisioning profile.") from exc
    provisioned_devices = provisioned.get("ProvisionedDevices", []) or []

    watch_udids = connected_watch_udids(timeout)
    if not watch_udids:
        print("Warning: no physical Apple Watch is visible; embedded profile device coverage was not verified.",
              file=sys.stderr)
        return

    for udid in watch_udids:
        if udid in provisioned_devices:
            print(f"==> Embedded Watch profile includes visible Apple Watch: {udid}")
            return

    raise SystemExit(
        "Embedded Watch provisioning profile does not include any visible Apple Watch.\n"
        "Open Xcode with the paired iPhone connected, enable Developer Mode on the Watch, "
        "register the Watch, and run this script again so automatic signing can refresh."
    )


def validate_embedded_watch_companion(ios_app: Path, watch_app: Path, timeout: str) -> None:
    require_app_bundle(watch_app, "embedded watchOS companion")

    ios_bundle_id = plist_value(ios_app / "Info.plist", "CFBundleIdentifier")
    watch_bundle_id = plist_value(watch_app / "Info.plist", "CFBundleIdentifier")
    companion_bundle_id = plist_value(watch_app / "Info.plist", "WKCompanionAppBundleIdentifier")
    runs_independently = plist_value(watch_app / "Info.plist", "WKRunsIndependentlyOfCompanionApp")
    is_watch_app = plist_value(watch_app / "Info.plist", "WKApplication")

    if watch_bundle_id != f"{ios_bundle_id}.watchkitapp":
        raise SystemExit(
            f"Embedded Watch bundle ID must be {ios_bundle_id}.watchkitapp, found: {watch_bundle_id}"
        )
    if companion_bundle_id != ios_bundle_id:
        raise SystemExit(
            f"Embedded Watch companion ID must be {ios_bundle_id}, found: {companion_bundle_id}"
        )
    if runs_independently not in FALSEISH:
        raise SystemExit("Embedded Watch app must depend on its iPhone companion.")
    if is_watch_app not in TRUEISH:
        raise SystemExit("Embedded bundle is not marked as a watchOS application.")

    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(watch_app)], check=True)
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(ios_app)], check=True)
    validate_embedded_watch_profile(watch_app, timeout)
    print(f"==> iOS app contains dependent Watch companion: {watch_bundle_id}")


def available_ios_devices_json(json_path: Path, timeout: str) -> None:
    flt = (
        "(State BEGINSWITH 'available' OR State BEGINSWITH 'connected') "
        "AND hardwareProperties.platform == 'iOS' "
        "AND hardwareProperties.reality == 'physical' "
        "AND deviceProperties.developerModeStatus == 'enabled'"
    )
    run(
        ["xcrun", "devicectl", "list", "devices", "--filter", flt,
         "--timeout", str(timeout), "--json-output", str(json_path)],
        check=True,
    )


def device_entries_from_json(json_path: Path) -> list[tuple[str, str]]:
    with json_path.open("rb") as handle:
        payload = json.load(handle)
    entries: list[tuple[str, str]] = []
    for device in payload.get("result", {}).get("devices", []):
        identifier = device.get("identifier")
        name = device.get("deviceProperties", {}).get("name", "Unknown Device")
        if identifier:
            entries.append((identifier, name))
    return entries


def install_app_on_device(
    device_id: str, device_name: str, app_path: Path, platform_label: str,
    launch_bundle_id: str, launch_after_install: bool, failures: list[str],
) -> None:
    print(f"==> Installing {platform_label} app on {device_name} ({device_id})")
    result = run(
        ["xcrun", "devicectl", "device", "install", "app", "--device", device_id, str(app_path)],
        check=False,
    )
    if result.returncode == 0:
        if launch_bundle_id and launch_after_install:
            print(f"==> Launching on {device_name}")
            launch = run(
                ["xcrun", "devicectl", "device", "process", "launch", "--device", device_id, launch_bundle_id],
                check=False,
            )
            if launch.returncode != 0:
                failures.append(f"{device_name} launch")
    else:
        failures.append(f"{device_name} install")


def install_on_available_ios_devices(
    ios_app: Path, bundle_id: str, timeout: str, launch_after_install: bool, failures: list[str],
) -> None:
    print("==> Looking for available or connected physical iOS/iPadOS development devices")
    with tempfile.NamedTemporaryFile(prefix="timetracker-devices.", suffix=".json", delete=False) as tmp:
        json_path = Path(tmp.name)
    try:
        available_ios_devices_json(json_path, timeout)
        entries = device_entries_from_json(json_path)
    finally:
        try:
            json_path.unlink()
        except OSError:
            pass

    if not entries:
        print("No available physical iOS/iPadOS development devices found. Skipping device install.")
        return

    for device_id, device_name in entries:
        install_app_on_device(
            device_id, device_name, ios_app, "iOS/iPadOS", bundle_id, launch_after_install, failures
        )


def report_device_failures(failures: list[str], allow_failures: bool) -> None:
    if not failures:
        return
    print("Some device operations failed:", file=sys.stderr)
    for entry in failures:
        print(f"  - {entry}", file=sys.stderr)
    if not allow_failures:
        raise SystemExit(1)


def copy_mac_app_to_applications(
    mac_app: Path, product_name: str, applications_dir: str,
) -> Path:
    require_app_bundle(mac_app, "macOS")
    mac_dest = Path(applications_dir) / f"{product_name}.app"

    unsafe = (
        not product_name
        or "/" in product_name
        or product_name in (".", "..")
    )
    if unsafe or not str(mac_dest).startswith(f"{applications_dir.rstrip('/')}/") or not str(mac_dest).endswith(".app"):
        raise SystemExit(f"Refusing to replace an unsafe Applications path: {mac_dest}")

    temp_dest = Path(applications_dir) / f".{product_name}.app.installing.{os.getpid()}"
    print(f"==> Copying macOS app to {mac_dest}")
    if temp_dest.exists():
        import shutil
        shutil.rmtree(temp_dest, ignore_errors=True)
    run(["ditto", str(mac_app), str(temp_dest)], check=True)
    if mac_dest.exists():
        import shutil
        shutil.rmtree(mac_dest, ignore_errors=True)
    run(["mv", str(temp_dest), str(mac_dest)], check=True)
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(mac_dest)], check=True)
    return mac_dest


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    project = env("PROJECT", str(root / "timetracker.xcodeproj"))
    scheme = env("SCHEME", "timetracker")
    configuration = env("CONFIGURATION", "Debug")
    team_id = os.environ.get("DEVELOPMENT_TEAM", "LT98S43NKA")
    product_name = env("PRODUCT_NAME", "timetracker")
    watch_product_name = env("WATCH_PRODUCT_NAME", "timetrackerWatchApp")
    bundle_id = env("BUNDLE_ID", "me.mezorewww.timetracker")
    applications_dir = env("APPLICATIONS_DIR", "/Applications")
    device_timeout = env("DEVICE_TIMEOUT", "30")
    launch_after_install = os.environ.get("LAUNCH_AFTER_INSTALL", "0") == "1"
    allow_device_failures = os.environ.get("ALLOW_DEVICE_FAILURES", "0") == "1"

    build_root = root / "build" / "Install"
    derived_data = build_root / "DerivedData"
    ios_products = derived_data / "Build" / "Products" / f"{configuration}-iphoneos"
    mac_products = derived_data / "Build" / "Products" / configuration
    ios_app = ios_products / f"{product_name}.app"
    ios_embedded_watch_app = ios_app / "Watch" / f"{watch_product_name}.app"
    mac_app = mac_products / f"{product_name}.app"

    build_root.mkdir(parents=True, exist_ok=True)
    derived_data.mkdir(parents=True, exist_ok=True)

    failures: list[str] = []

    def run_xcodebuild(scheme_name: str, *extra: str) -> None:
        run([
            "xcodebuild",
            "-project", project,
            "-scheme", scheme_name,
            "-configuration", configuration,
            "-derivedDataPath", str(derived_data),
            f"DEVELOPMENT_TEAM={team_id}",
            "-allowProvisioningUpdates",
            "-allowProvisioningDeviceRegistration",
            *extra,
        ], check=True)

    print(f"==> Building iOS/iPadOS app with embedded Watch companion ({configuration}, team {team_id})")
    run_xcodebuild(scheme, "-sdk", "iphoneos", "-destination", "generic/platform=iOS", "build")
    require_app_bundle(ios_app, "iOS")
    validate_embedded_watch_companion(ios_app, ios_embedded_watch_app, device_timeout)
    install_on_available_ios_devices(ios_app, bundle_id, device_timeout, launch_after_install, failures)

    print(f"==> Building macOS app ({configuration}, team {team_id})")
    run_xcodebuild(scheme, "-destination", "generic/platform=macOS", "build")
    mac_dest = copy_mac_app_to_applications(mac_app, product_name, applications_dir)
    report_device_failures(failures, allow_device_failures)

    print(
        f"\nDone.\n"
        f"iOS app:       {ios_app}\n"
        f"embedded watch: {ios_embedded_watch_app}\n"
        f"macOS app:     {mac_dest}\n"
        f"Derived data:  {derived_data}\n\n"
        "The paired Apple Watch installs the embedded companion when Automatic App Install "
        "is enabled in the iPhone Watch app.\n\n"
        "Tips:\n"
        "  CONFIGURATION=Release make build-install-all\n"
        "  LAUNCH_AFTER_INSTALL=1 make build-install-all\n"
        "  ALLOW_DEVICE_FAILURES=1 make build-install-all\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())