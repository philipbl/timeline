
PYTHON := $(shell if [ -x .venv/bin/python ]; then printf '%s' .venv/bin/python; else printf '%s' python3; fi)

timeline.pdf: events.yaml timeline.py
	$(PYTHON) timeline.py events.yaml

.PHONY: test
test:
	$(PYTHON) -m pytest
