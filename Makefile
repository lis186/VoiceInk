# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework

.PHONY: all clean whisper setup build local check healthcheck help dev run share

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building VoiceInk for local use (no Apple Developer certificate required)..."
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS=$(CURDIR)/VoiceInk/VoiceInk.local.entitlements \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -path "*/Debug/*" -not -path "*/Index.noindex/*" -type d | head -1) && \
	if [ -n "$$APP_PATH" ]; then \
		echo "Copying VoiceInk.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/VoiceInk.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/VoiceInk.app"; \
		xattr -cr "$$HOME/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/VoiceInk.app"; \
		echo "Run with: open ~/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app in DerivedData."; \
		exit 1; \
	fi

# Run application
run:
	@if [ -d "$$HOME/Downloads/VoiceInk.app" ]; then \
		echo "Opening ~/Downloads/VoiceInk.app..."; \
		open "$$HOME/Downloads/VoiceInk.app"; \
	else \
		echo "Looking for VoiceInk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -not -path "*/Index.noindex/*" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "VoiceInk.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Package app + install script for sharing (no Apple Developer certificate)
share:
	@if [ ! -d "$$HOME/Downloads/VoiceInk.app" ]; then \
		echo "Error: ~/Downloads/VoiceInk.app not found. Run 'make local' first."; \
		exit 1; \
	fi
	@echo "Packaging VoiceInk for sharing..."
	@STAGING="$$HOME/Downloads/VoiceInk-share" && \
	rm -rf "$$STAGING" && \
	mkdir -p "$$STAGING" && \
	ditto "$$HOME/Downloads/VoiceInk.app" "$$STAGING/VoiceInk.app" && \
	printf '#!/bin/bash\nset -e\nSCRIPT_DIR="$$(cd "$$(dirname "$$0")" && pwd)"\nAPP="$$SCRIPT_DIR/VoiceInk.app"\necho "正在安裝 VoiceInk..."\nxattr -cr "$$APP"\ncp -R "$$APP" /Applications/\nxattr -cr /Applications/VoiceInk.app\necho ""\necho "安裝完成！正在啟動 VoiceInk..."\necho ""\necho "首次啟動請依序授予以下權限（按錄音鍵即可觸發授權視窗）："\necho "  - 輔助使用（Accessibility）"\necho "  - 螢幕錄影（Screen Recording）"\necho "  - 麥克風（Microphone）"\necho ""\necho "【推薦使用本地模型 Qwen3-ASR 0.6B (MLX)】"\necho "此版本內建 Qwen3-ASR，支援 52 種語言及 22 種中文方言，"\necho "完全離線執行、不需 API 金鑰，中英夾雜辨識效果優異。"\necho "設定方式：左側選單點選 AI Models → 上方切換至 Local → 下載 Qwen3-ASR 0.6B (MLX)"\necho ""\nopen /Applications/VoiceInk.app\n' > "$$STAGING/install.sh" && \
	chmod +x "$$STAGING/install.sh" && \
	rm -f "$$HOME/Downloads/VoiceInk-share.zip" && \
	ditto -c -k --sequesterRsrc "$$STAGING" "$$HOME/Downloads/VoiceInk-share.zip" && \
	rm -rf "$$STAGING" && \
	echo "" && \
	echo "Package ready: ~/Downloads/VoiceInk-share.zip" && \
	echo "" && \
	echo "Instructions for recipient:" && \
	echo "  1. Unzip VoiceInk-share.zip" && \
	echo "  2. Open Terminal, cd to the unzipped folder" && \
	echo "  3. Run: bash install.sh"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  share              Package app + install script into ~/Downloads/VoiceInk-share.zip"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"