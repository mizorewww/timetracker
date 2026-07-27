# Timetracker — 统一入口:构建、发布、版本与钩子。
# 详见 `make help` 与 Docs/DevelopmentTools.md。脚本本体退化为 scripts/ 下的 uv run wrapper,
# 实现位于 tools/timetracker_tools/。

SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

PROJECT          := timetracker.xcodeproj
SCHEME           := timetracker
DEVELOPMENT_TEAM ?= LT98S43NKA
CONFIGURATION    ?= Debug
TEST_ONLY        ?= timetrackerTests
SCRIPTS          := scripts
LIVE_LLM_UI_DEVICE_TYPE ?= com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
LIVE_LLM_UI_RUNTIME ?= com.apple.CoreSimulator.SimRuntime.iOS-27-0
UI_TEST_DEVICE_TYPE ?= com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
UI_TEST_RUNTIME ?= com.apple.CoreSimulator.SimRuntime.iOS-27-0
UI_TEST_ONLY ?= timetrackerUITests/timetrackerUITests
UI_TEST_RESULT_ROOT ?= build/UITestResults

-include .env
export TIMETRACKER_LIVE_LLM_API_KEY

.PHONY: help
help: ## 列出所有目标
	@echo "Timetracker 开发入口(详见 Docs/DevelopmentTools.md)。运行 make <目标> 即可。"
	@echo
	@awk 'BEGIN {FS = ":.*##"} \
	         /^# ── / { sub(/^# ── +/,""); sub(/ +──+$$/,""); print "\n" $$0; next } \
	         /^[a-zA-Z][a-zA-Z0-9_-]*:.*##/ { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ── 概览 ──────────────────────────────────────────────────────
.PHONY: venv
venv: ## 用 uv 创建/同步 .venv(也可由 wrapper 自举)
	uv sync

# ── Hooks & 版本 ──────────────────────────────────────────────
.PHONY: install-hooks
install-hooks: ## 安装 pre-commit 版本钩子(clone 后执行一次)
	@$(SCRIPTS)/install_git_hooks.sh

.PHONY: check-hooks
check-hooks: ## 只读校验钩子是否就位
	@$(SCRIPTS)/install_git_hooks.sh --check

.PHONY: stage-version
stage-version: ## pre-commit 内部调用:把下一版本写入 index 与工作树
	@$(SCRIPTS)/stage_commit_version.sh

.PHONY: bump-version
bump-version: ## 手动递增 marketing/build 版本(正常提交无需运行)
	@$(SCRIPTS)/bump_marketing_version.sh

.PHONY: test-versioning
test-versioning: ## 隔离临时仓库中跑版本钩子集成测试
	@$(SCRIPTS)/test_versioning_hooks.sh

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
	@$(SCRIPTS)/build_install_all.sh

.PHONY: test
test: ## macOS 单元测试(timetrackerTests)
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=macOS' -only-testing:$(TEST_ONLY) \
	  -parallel-testing-enabled NO

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
	    -destination "platform=iOS Simulator,id=$$simulator_udid" \
	    -resultBundlePath "$$result_bundle" \
	    -only-testing:$(UI_TEST_ONLY) \
	    -parallel-testing-enabled NO \
	    -maximum-parallel-testing-workers 1

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

.PHONY: test-llm-live
test-llm-live: ## 用真实 DeepSeek API 验证三条提示词与任务计划(prompts/prompt28/prompt150/all)
	@test -n "$${TIMETRACKER_LIVE_LLM_API_KEY:-}" || \
	  { echo "TIMETRACKER_LIVE_LLM_API_KEY must be set in the environment or .env" >&2; exit 2; }
	@set -eu; \
	  live_dir="$(CURDIR)/build/LiveLLMHarness"; \
	  mkdir -p "$$live_dir"; \
	  umask 077; \
	  printf '%s' "$${TIMETRACKER_LIVE_LLM_API_KEY}" > "$$live_dir/api-key"; \
	  printf '%s' "$${TIMETRACKER_LIVE_LLM_SCENARIO:-prompt28}" > "$$live_dir/scenario"; \
	  printf '%s' "$${TIMETRACKER_LIVE_LLM_ENDPOINT:-https://api.deepseek.com}" > "$$live_dir/endpoint"; \
	  printf '%s' "$${TIMETRACKER_LIVE_LLM_MODEL:-deepseek-v4-flash}" > "$$live_dir/model"; \
	  : > "$$live_dir/run"; \
	  cleanup_live_llm() { \
	    for name in run api-key scenario endpoint model; do \
	      test ! -e "$$live_dir/$$name" || unlink "$$live_dir/$$name"; \
	    done; \
	    rmdir "$$live_dir" 2>/dev/null || true; \
	  }; \
	  trap cleanup_live_llm EXIT INT TERM; \
	  xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	    -destination 'platform=macOS' \
	    -only-testing:timetrackerTests/LiveDeepSeekTaskWorkspaceTests \
	    -parallel-testing-enabled NO

.PHONY: test-llm-live-ui
test-llm-live-ui: ## 在临时 iPhone 模拟器中用真实 DeepSeek 验证 Generate/Preview/Apply
	@test -n "$${TIMETRACKER_LIVE_LLM_API_KEY:-}" || \
	  { echo "TIMETRACKER_LIVE_LLM_API_KEY must be set in the environment or .env" >&2; exit 2; }
	@set -eu; \
	  live_dir="$(CURDIR)/build/LiveLLMUIHarness"; \
	  run_id="$$(date +%Y%m%d-%H%M%S)"; \
	  screenshot_dir="$$live_dir/screenshots-$$run_id"; \
	  result_bundle="$$live_dir/LiveLLMUI-$$run_id.xcresult"; \
	  mkdir -p "$$live_dir" "$$screenshot_dir"; \
	  umask 077; \
	  printf '%s' "$${TIMETRACKER_LIVE_LLM_API_KEY}" > "$$live_dir/api-key"; \
	  printf '%s' "$${TIMETRACKER_LIVE_LLM_ENDPOINT:-https://api.deepseek.com}" > "$$live_dir/endpoint"; \
	  printf '%s' "$${TIMETRACKER_LIVE_LLM_MODEL:-deepseek-v4-flash}" > "$$live_dir/model"; \
	  printf '%s' "$$screenshot_dir" > "$$live_dir/screenshot-dir"; \
	  : > "$$live_dir/run"; \
	  simulator_udid="$$(xcrun simctl create \
	    "TimeTracker Live LLM $$run_id" \
	    "$(LIVE_LLM_UI_DEVICE_TYPE)" \
	    "$(LIVE_LLM_UI_RUNTIME)")"; \
	  printf '%s' "$$simulator_udid" > "$$live_dir/simulator-udid"; \
	  cleanup_live_llm_ui() { \
	    xcrun simctl terminate "$$simulator_udid" me.mezorewww.timetracker >/dev/null 2>&1 || true; \
	    xcrun simctl shutdown "$$simulator_udid" >/dev/null 2>&1 || true; \
	    xcrun simctl delete "$$simulator_udid" >/dev/null 2>&1 || true; \
	    for name in run api-key endpoint model screenshot-dir simulator-udid; do \
	      test ! -e "$$live_dir/$$name" || unlink "$$live_dir/$$name"; \
	    done; \
	  }; \
	  trap cleanup_live_llm_ui EXIT INT TERM; \
	  xcrun simctl boot "$$simulator_udid"; \
	  xcrun simctl bootstatus "$$simulator_udid" -b; \
	  xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	    -destination "platform=iOS Simulator,id=$$simulator_udid" \
	    -resultBundlePath "$$result_bundle" \
	    -only-testing:timetrackerUITests/timetrackerUITests/testLiveDeepSeekTaskPlanGeneratePreviewAndApply \
	    -parallel-testing-enabled NO \
	    -maximum-parallel-testing-workers 1

# ── 校验 ──────────────────────────────────────────────────────
.PHONY: localization-check
localization-check: ## 校验所有 .strings 资源在三语种间 key 一致
	@$(SCRIPTS)/localization_check.sh

# ── 格式化 ────────────────────────────────────────────────────
.PHONY: format
format: ## 用 SwiftFormat 原地格式化所有 Swift 源
	@$(SCRIPTS)/format.sh

.PHONY: format-check
format-check: ## 只读校验 Swift 源是否符合 SwiftFormat(不修改)
	@$(SCRIPTS)/format.sh --check

# ── 发布 ──────────────────────────────────────────────────────
.PHONY: export-artifacts
export-artifacts: ## 归档并导出签名产物(iOS IPA + macOS app/zip)
	@$(SCRIPTS)/export_signed_artifacts.sh

.PHONY: build-info
build-info: ## 写入 AppBuildInfo.plist(通常由 Xcode 构建阶段调用)
	@$(SCRIPTS)/write_build_info_plist.sh

# ── 清理 ──────────────────────────────────────────────────────
.PHONY: clean
clean: ## 删除 build/ 下的导出、归档与安装产物
	rm -rf build/Exports build/Archives build/Install
