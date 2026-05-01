SHELL := /bin/bash

TARGET ?=

.PHONY: help install
.PHONY: link-global link-project verify-project

help:
	@echo "Targets:"
	@echo "  link-global   Symlink dotagents -> ~/.agents (global)"
	@echo "  link-project  Setup <project>/.agents and link .cursor/.codex/.claude (TARGET required)"
	@echo "  verify-project Basic verification that SKILL.md is visible (TARGET required)"
	@echo "  install        (legacy) rsync dotagents -> <project>/.agents (TARGET required)"

install:
	@if [[ -z "$(TARGET)" ]]; then \
		echo "ERROR: TARGET is required. Example: make install TARGET=../my-project" >&2; \
		exit 2; \
	fi
	@./scripts/sync-agents.sh --target "$(TARGET)"

link-global:
	@./scripts/link-dotagents.sh --home --all

link-project:
	@if [[ -z "$(TARGET)" ]]; then \
		echo "ERROR: TARGET is required. Example: make link-project TARGET=../my-project" >&2; \
		exit 2; \
	fi
	@./scripts/link-project-agents.sh --target "$(TARGET)"

verify-project:
	@if [[ -z "$(TARGET)" ]]; then \
		echo "ERROR: TARGET is required. Example: make verify-project TARGET=../my-project" >&2; \
		exit 2; \
	fi
	@./scripts/verify-project-links.sh --target "$(TARGET)"
