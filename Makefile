
PYTHON := $(shell if [ -x .venv/bin/python ]; then printf '%s' .venv/bin/python; else printf '%s' python3; fi)

timeline.pdf: events.yaml timeline.py
	$(PYTHON) timeline.py events.yaml

.PHONY: test
test:
	$(PYTHON) -m pytest

.PHONY: lint
lint:
	$(PYTHON) -m ruff check .

# Native Mac app
.PHONY: app
app:
	cd TimelineApp && swift build -c release
	rm -rf build/Timeline.app
	mkdir -p build/Timeline.app/Contents/MacOS
	cp TimelineApp/.build/release/TimelineApp build/Timeline.app/Contents/MacOS/Timeline
	cp TimelineApp/Info.plist build/Timeline.app/Contents/Info.plist
	codesign --force -s - build/Timeline.app

.PHONY: run-app
run-app: app
	open build/Timeline.app
