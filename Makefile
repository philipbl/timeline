APP := build/Timeline.app

.PHONY: app
app:
	cd TimelineApp && swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp TimelineApp/.build/release/TimelineApp $(APP)/Contents/MacOS/Timeline
	cp TimelineApp/Info.plist $(APP)/Contents/Info.plist
	cp TimelineApp/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp TimelineApp/DocIcon.icns $(APP)/Contents/Resources/DocIcon.icns
	# Quick Look preview extension
	mkdir -p $(APP)/Contents/PlugIns/TimelinePreview.appex/Contents/MacOS
	cp TimelineApp/.build/release/TimelineQuickLook \
		$(APP)/Contents/PlugIns/TimelinePreview.appex/Contents/MacOS/TimelinePreview
	cp TimelineApp/QuickLookInfo.plist \
		$(APP)/Contents/PlugIns/TimelinePreview.appex/Contents/Info.plist
	codesign --force -s - --entitlements TimelineApp/quicklook.entitlements \
		$(APP)/Contents/PlugIns/TimelinePreview.appex
	# Quick Look thumbnail extension
	mkdir -p $(APP)/Contents/PlugIns/TimelineThumbnail.appex/Contents/MacOS
	cp TimelineApp/.build/release/TimelineThumbnail \
		$(APP)/Contents/PlugIns/TimelineThumbnail.appex/Contents/MacOS/TimelineThumbnail
	cp TimelineApp/ThumbnailInfo.plist \
		$(APP)/Contents/PlugIns/TimelineThumbnail.appex/Contents/Info.plist
	codesign --force -s - --entitlements TimelineApp/quicklook.entitlements \
		$(APP)/Contents/PlugIns/TimelineThumbnail.appex
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

.PHONY: doc-icon
doc-icon:
	cd TimelineApp && swift scripts/make_doc_icon.swift /tmp/doc_1024.png
	rm -rf /tmp/DocIcon.iconset && mkdir /tmp/DocIcon.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s /tmp/doc_1024.png --out /tmp/DocIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s*2)); \
		sips -z $$d $$d /tmp/doc_1024.png --out /tmp/DocIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns /tmp/DocIcon.iconset -o TimelineApp/DocIcon.icns

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
