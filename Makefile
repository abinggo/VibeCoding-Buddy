.PHONY: build run clean bundle bundle-universal dmg

APP_NAME = Vibe Buddy
BUNDLE_DIR = build/$(APP_NAME).app
EXECUTABLE = VibeBuddy

build:
	swift build

release:
	swift build -c release

# Build universal binary (Intel + Apple Silicon)
release-universal:
	swift build -c release --arch arm64 --arch x86_64

run: build
	.build/debug/$(EXECUTABLE)

clean:
	swift package clean
	rm -rf build/

bundle: release
	mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	cp .build/release/$(EXECUTABLE) "$(BUNDLE_DIR)/Contents/MacOS/"
	cp Info.plist "$(BUNDLE_DIR)/Contents/"
	@if [ -d ".build/release/VibeBuddy_VibeBuddy.bundle" ]; then \
		cp -R .build/release/VibeBuddy_VibeBuddy.bundle "$(BUNDLE_DIR)/Contents/Resources/"; \
	fi
	@echo "Built $(BUNDLE_DIR)"

# Build universal .app (Intel + Apple Silicon)
bundle-universal: release-universal
	mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	cp .build/apple/Products/Release/$(EXECUTABLE) "$(BUNDLE_DIR)/Contents/MacOS/"
	cp Info.plist "$(BUNDLE_DIR)/Contents/"
	@if [ -d ".build/apple/Products/Release/VibeBuddy_VibeBuddy.bundle" ]; then \
		cp -R .build/apple/Products/Release/VibeBuddy_VibeBuddy.bundle "$(BUNDLE_DIR)/Contents/Resources/"; \
	fi
	@echo "Built universal $(BUNDLE_DIR)"

dmg: bundle
	hdiutil create -volname "Vibe Buddy" -srcfolder "$(BUNDLE_DIR)" -ov -format UDZO build/VibeBuddy.dmg
	@echo "Created build/VibeBuddy.dmg"
