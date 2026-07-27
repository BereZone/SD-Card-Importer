# SD Card File Importer
#
# Version automation. MARKETING_VERSION in the Xcode project is the single
# source of truth; every target below reads from or writes to it, and nothing
# should edit it by hand.
#
# Run `make help` for the target list.

PROJECT      := SD Card File Importer.xcodeproj
SCHEME       := SD Card File Importer
APP_NAME     := SD Card File Importer
PBXPROJ      := $(PROJECT)/project.pbxproj
CHANGELOG    := CHANGELOG.md
BUILD_DIR    := build

# Strict semver: MAJOR.MINOR.PATCH with optional prerelease and build metadata.
SEMVER_RE := ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$$

VERSION := $(shell grep -m1 'MARKETING_VERSION' '$(PBXPROJ)' | sed 's/.*= *//; s/;//' | tr -d ' ')

.PHONY: help version build debug run clean test bump tag untag release-check

help:
	@echo "SD Card File Importer - current version $(VERSION)"
	@echo ""
	@echo "  make build              Release build"
	@echo "  make debug              Debug build"
	@echo "  make run                Build and launch"
	@echo "  make test               Run tests (skips if no test target exists)"
	@echo "  make clean              Remove build artifacts"
	@echo ""
	@echo "  make version            Print the current version"
	@echo "  make bump VERSION=x.y.z Bump MARKETING_VERSION (asks to confirm)"
	@echo "  make tag                Create an annotated tag for the current version"
	@echo "  make untag VERSION=x.y.z Delete a tag locally and on the remote"
	@echo "  make release-check      Verify version, changelog and tree are release-ready"

version:
	@echo "$(VERSION)"

# ---------------------------------------------------------------- build

build:
	@xcodebuild build -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-configuration Release -destination "platform=macOS" \
		CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO | \
		grep -E "error:|warning:|BUILD" || true
	@echo "Build finished."

debug:
	@xcodebuild build -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-configuration Debug -destination "platform=macOS" | \
		grep -E "error:|warning:|BUILD" || true

run: debug
	@APP_PATH=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-configuration Debug -showBuildSettings 2>/dev/null | \
		awk '/ BUILT_PRODUCTS_DIR =/ {print $$3}' | head -1); \
	open "$$APP_PATH/$(APP_NAME).app"

clean:
	@xcodebuild clean -project "$(PROJECT)" -scheme "$(SCHEME)" >/dev/null 2>&1 || true
	@rm -rf "$(BUILD_DIR)"
	@echo "Cleaned."

# Skip rather than fail when no test target exists, so this stays usable until
# one is added to the Xcode project.
test:
	@if xcodebuild -list -project "$(PROJECT)" -json 2>/dev/null | \
		grep -q '"[^"]*Tests"'; then \
		xcodebuild test -project "$(PROJECT)" -scheme "$(SCHEME)" \
			-destination "platform=macOS" | \
			grep -E "error:|Test Suite|BUILD|TEST" || true; \
	else \
		echo "No test target in the Xcode project - skipping."; \
		echo "Add one in Xcode and this will start running automatically."; \
	fi

# ---------------------------------------------------------------- versioning

bump:
	@if [ "$(origin VERSION)" != "command line" ]; then \
		echo "error: specify a version, e.g. make bump VERSION=1.1.0"; exit 1; \
	fi
	@NEW="$(VERSION)"; \
	CUR=$$(grep -m1 'MARKETING_VERSION' '$(PBXPROJ)' | sed 's/.*= *//; s/;//' | tr -d ' '); \
	case "$$NEW" in v*) \
		echo "error: drop the leading 'v' - pass the bare version, e.g. VERSION=$${NEW#v}"; \
		exit 1;; \
	esac; \
	if ! echo "$$NEW" | grep -Eq '$(SEMVER_RE)'; then \
		echo "error: '$$NEW' is not valid semver (expected MAJOR.MINOR.PATCH)"; exit 1; \
	fi; \
	if [ "$$CUR" = "$$NEW" ]; then \
		echo "MARKETING_VERSION is already $$NEW - nothing to do."; \
		echo "(Retrying a bump is safe; this is not an error.)"; \
		exit 0; \
	fi; \
	echo "Bump $$CUR -> $$NEW?"; \
	printf "Continue [y/N] "; read ans; \
	case "$$ans" in [yY]*) ;; *) echo "Aborted."; exit 1;; esac; \
	sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $$NEW;/g" '$(PBXPROJ)'; \
	echo "Updated MARKETING_VERSION to $$NEW."; \
	if ! grep -q "^## \[$$NEW\]" '$(CHANGELOG)'; then \
		echo ""; \
		echo "note: $(CHANGELOG) has no '## [$$NEW]' section yet."; \
		echo "      Move the [Unreleased] entries under a new heading before tagging."; \
	fi

tag: release-check
	@V="$(VERSION)"; \
	if git rev-parse "v$$V" >/dev/null 2>&1; then \
		echo "error: tag v$$V already exists."; \
		echo "       Delete it first with: make untag VERSION=$$V"; \
		exit 1; \
	fi; \
	echo "Create annotated tag v$$V at $$(git rev-parse --short HEAD)?"; \
	printf "Continue [y/N] "; read ans; \
	case "$$ans" in [yY]*) ;; *) echo "Aborted."; exit 1;; esac; \
	NOTES=$$(awk -v v="$$V" '$$0 ~ "^## \\[" v "\\]" {f=1;next} f && (/^## / || /^\[[^]]+\]:/) {f=0} f' '$(CHANGELOG)'); \
	git tag -a "v$$V" -m "v$$V" -m "$$NOTES"; \
	echo "Created v$$V. Push it with:"; \
	echo "  git push --follow-tags"

untag:
	@if [ "$(origin VERSION)" != "command line" ]; then \
		echo "error: specify a version, e.g. make untag VERSION=1.1.0"; exit 1; \
	fi
	@V="$(VERSION)"; \
	V="$${V#v}"; \
	if ! git rev-parse "v$$V" >/dev/null 2>&1; then \
		echo "Tag v$$V does not exist locally."; \
	else \
		echo "Delete tag v$$V locally and on the remote?"; \
		printf "Continue [y/N] "; read ans; \
		case "$$ans" in [yY]*) ;; *) echo "Aborted."; exit 1;; esac; \
		git tag -d "v$$V"; \
		REMOTE=$$(git remote | head -1); \
		git push "$$REMOTE" ":refs/tags/v$$V" 2>/dev/null || \
			echo "(remote tag was already gone)"; \
	fi; \
	if command -v gh >/dev/null 2>&1 && gh release view "v$$V" >/dev/null 2>&1; then \
		echo ""; \
		echo "A GitHub release for v$$V still exists."; \
		echo "The release workflow upserts, so re-tagging will update it in place."; \
		printf "Delete the release too? [y/N] "; read ans2; \
		case "$$ans2" in [yY]*) gh release delete "v$$V" --yes && echo "Release deleted.";; \
			*) echo "Left the release in place.";; \
		esac; \
	fi

# Everything the release workflow will check, run locally so failures surface
# before a tag is pushed.
release-check:
	@V="$(VERSION)"; \
	FAIL=0; \
	if ! echo "$$V" | grep -Eq '$(SEMVER_RE)'; then \
		echo "FAIL  MARKETING_VERSION '$$V' is not valid semver"; FAIL=1; \
	else \
		echo "ok    MARKETING_VERSION is $$V"; \
	fi; \
	if ! grep -q "^## \[$$V\]" '$(CHANGELOG)'; then \
		echo "FAIL  $(CHANGELOG) has no '## [$$V]' section"; FAIL=1; \
	else \
		echo "ok    $(CHANGELOG) has a [$$V] section"; \
	fi; \
	if [ -n "$$(git status --porcelain)" ]; then \
		echo "FAIL  working tree is dirty"; FAIL=1; \
	else \
		echo "ok    working tree is clean"; \
	fi; \
	if [ "$$FAIL" != "0" ]; then exit 1; fi
