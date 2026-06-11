APP := build/Timeline.app

.PHONY: app
app:
	cd TimelineApp && swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp TimelineApp/.build/release/TimelineApp $(APP)/Contents/MacOS/Timeline
	cp TimelineApp/Info.plist $(APP)/Contents/Info.plist
	cp TimelineApp/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force -s - $(APP)

.PHONY: run-app
run-app: app
	open $(APP)

.PHONY: test
test:
	cd TimelineApp && swift build
	TimelineApp/.build/debug/TimelineApp --self-test

# README screenshots; also the golden images for CI's render check
.PHONY: docs
docs:
	cd TimelineApp && swift build
	TimelineApp/.build/debug/TimelineApp --render example.timeline docs/example.png
	TimelineApp/.build/debug/TimelineApp --render example.timeline docs/example-dark.png --dark

.PHONY: icon
icon:
	cd TimelineApp && swift scripts/make_icon.swift /tmp/icon_1024.png
	rm -rf /tmp/AppIcon.iconset && mkdir /tmp/AppIcon.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s /tmp/icon_1024.png --out /tmp/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s*2)); \
		sips -z $$d $$d /tmp/icon_1024.png --out /tmp/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns /tmp/AppIcon.iconset -o TimelineApp/AppIcon.icns
