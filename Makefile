# Timetracker — 唯一开发入口:构建、测试、发布、版本与钩子。
# Xcode 构建阶段与 pre-commit 钩子也经由本文件;Python 实现位于 tools/timetracker_tools/。

SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

PROJECT          := timetracker.xcodeproj
SCHEME           := timetracker
DEVELOPMENT_TEAM ?= LT98S43NKA
CONFIGURATION    ?= Debug
TEST_ONLY        ?= timetrackerTests
SWIFT_ROOTS      := timetracker timetrackerTests timetrackerUITests timetrackerWatchApp \
                    timetrackerWidgetExtension timetrackerLiveActivityExtension SharedLiveActivity
LOCALIZATION_FLAGS ?=
UI_TEST_DEVICE_TYPE ?= com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
UI_TEST_RUNTIME ?= com.apple.CoreSimulator.SimRuntime.iOS-27-0
UI_TEST_ONLY ?= timetrackerUITests/AdaptiveShellUITests
UI_TEST_CONFIGURATION ?= Debug
UI_TEST_RESULT_ROOT ?= build/UITestResults

-include .env

# Xcode 构建阶段与 GUI git 客户端的 PATH 不含 Homebrew / uv 安装目录。
export PATH := /opt/homebrew/bin:/usr/local/bin:$(HOME)/.local/bin:$(HOME)/.cargo/bin:$(PATH)
TOOL := uv run --quiet --project $(CURDIR) python -m timetracker_tools

.PHONY: help
help: ## 列出所有目标
	@echo "Timetracker 开发入口(详见 README.md)。运行 make <目标> 即可。"
	@echo
	@awk 'BEGIN {FS = ":.*##"} \
	         /^# ── / { sub(/^# ── +/,""); sub(/ +──+$$/,""); print "\n" $$0; next } \
	         /^[a-zA-Z][a-zA-Z0-9_-]*:.*##/ { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ── 概览 ──────────────────────────────────────────────────────
.PHONY: venv
venv: ## 用 uv 创建/同步 .venv(工具目标首次运行时也会自举)
	uv sync

# ── Hooks & 版本 ──────────────────────────────────────────────
.PHONY: install-hooks
install-hooks: ## 安装 pre-commit localization 闸门钩子(clone 后执行一次)
	@$(TOOL).install_git_hooks

.PHONY: check-hooks
check-hooks: ## 只读校验钩子是否就位
	@$(TOOL).install_git_hooks --check

.PHONY: bump-version
bump-version: ## 发布前手动递增 marketing/build 版本(见 Docs/Versioning.md)
	@$(TOOL).bump_marketing_version

# ── 构建 / 测试 ────────────────────────────────────────────────
.PHONY: build-ios
build-ios: ## 构建 iOS app(generic/platform=iOS)
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) -destination 'generic/platform=iOS' \
	  DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) -allowProvisioningUpdates

.PHONY: build-macos
build-macos: ## 构建 macOS app(generic/platform=macOS)
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) -destination 'generic/platform=macOS' \
	  DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) -allowProvisioningUpdates

.PHONY: build-install-all
build-install-all: ## 构建 iOS+Watch 与 macOS(默认 Release),安装到设备并复制到 /Applications
	@$(TOOL).build_install_all

.PHONY: test
test: ## macOS 单元测试(timetrackerTests)
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) \
	  -destination 'platform=macOS' -only-testing:$(TEST_ONLY) \
	  -parallel-testing-enabled NO ENABLE_TESTABILITY=YES

.PHONY: test-ui-ios
test-ui-ios: ## 在自清理的临时 iOS 模拟器中运行所选 XCUITest
	@set -eu; \
	  run_id="$$(date +%Y%m%d-%H%M%S)"; \
	  result_root="$(CURDIR)/$(UI_TEST_RESULT_ROOT)"; \
	  result_bundle="$$result_root/iOS-$$run_id.xcresult"; \
	  mkdir -p "$$result_root"; \
	  simulator_udid="$$(xcrun simctl create \
	    "TimeTracker UI $$run_id" \
	    "$(UI_TEST_DEVICE_TYPE)" \
	    "$(UI_TEST_RUNTIME)")"; \
	  cleanup_ui_test() { \
	    xcrun simctl terminate "$$simulator_udid" me.mezorewww.timetracker >/dev/null 2>&1 || true; \
	    xcrun simctl shutdown "$$simulator_udid" >/dev/null 2>&1 || true; \
	    xcrun simctl delete "$$simulator_udid" >/dev/null 2>&1 || true; \
	  }; \
	  trap cleanup_ui_test EXIT INT TERM; \
	  xcrun simctl boot "$$simulator_udid"; \
	  xcrun simctl bootstatus "$$simulator_udid" -b; \
	  xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	    -configuration "$(UI_TEST_CONFIGURATION)" \
	    -destination "platform=iOS Simulator,id=$$simulator_udid" \
	    -resultBundlePath "$$result_bundle" \
	    -only-testing:$(UI_TEST_ONLY) \
	    -skip-testing:timetrackerTests \
	    -parallel-testing-enabled NO \
	    -maximum-parallel-testing-workers 1 \
	    ENABLE_TESTABILITY=YES \
	    SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG

.PHONY: test-ui-macos
test-ui-macos: ## 在 macOS 上运行所选 XCUITest
	@set -eu; \
	  run_id="$$(date +%Y%m%d-%H%M%S)"; \
	  result_root="$(CURDIR)/$(UI_TEST_RESULT_ROOT)"; \
	  result_bundle="$$result_root/macOS-$$run_id.xcresult"; \
	  mkdir -p "$$result_root"; \
	  xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	    -destination 'platform=macOS' \
	    -resultBundlePath "$$result_bundle" \
	    -only-testing:$(UI_TEST_ONLY) \
	    -parallel-testing-enabled NO

# ── 校验 ──────────────────────────────────────────────────────
.PHONY: localization-check
localization-check: ## 校验所有 .strings 资源在三语种间 key 一致
	@$(TOOL).localization_check $(LOCALIZATION_FLAGS)

# ── 格式化 ────────────────────────────────────────────────────
.PHONY: format
format: ## 用 SwiftFormat 原地格式化所有 Swift 源
	swiftformat --config .swiftformat $(SWIFT_ROOTS)

.PHONY: format-check
format-check: ## 只读校验 Swift 源是否符合 SwiftFormat(不修改)
	swiftformat $(SWIFT_ROOTS) --config .swiftformat --lint

# ── 发布 ──────────────────────────────────────────────────────
.PHONY: export-artifacts
export-artifacts: ## 归档并导出签名产物(iOS IPA + macOS app/zip)
	@$(TOOL).export_signed_artifacts

.PHONY: build-info
build-info: ## 写入 AppBuildInfo.plist(通常由 Xcode 构建阶段调用)
	@$(TOOL).write_build_info_plist

# ── 清理 ──────────────────────────────────────────────────────
.PHONY: clean
clean: ## 删除 build/ 下的导出、归档与安装产物
	rm -rf build/Exports build/Archives build/Install
