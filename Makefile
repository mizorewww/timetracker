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
SCRIPTS          := scripts

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
build-install-all: ## 构建 iOS+Watch 与 macOS,安装到设备并复制到 /Applications
	@$(SCRIPTS)/build_install_all.sh

.PHONY: test
test: ## macOS 单元测试(timetrackerTests)
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=macOS' -only-testing:timetrackerTests \
	  -parallel-testing-enabled NO

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