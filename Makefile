.PHONY: build run clean bundle dmg

APP_NAME = Vibe Buddy
BUNDLE_DIR = build/$(APP_NAME).app
EXECUTABLE = VibeBuddy

build:
	swift build

release:
	swift build -c release

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
	@echo "Built $(BUNDLE_DIR)"

dmg: bundle
	hdiutil create -volname "Vibe Buddy" -srcfolder "$(BUNDLE_DIR)" -ov -format UDZO build/VibeBuddy.dmg
	@echo "Created build/VibeBuddy.dmg"
