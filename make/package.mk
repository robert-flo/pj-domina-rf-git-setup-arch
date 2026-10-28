# ═══════════════════════════════════════════════════════════════
# 📦 PACKAGE WORKFLOWS - Build, install, validate, and clean
# ═══════════════════════════════════════════════════════════════
# 🎯 Purpose: Provide safe, memorable shortcuts for Arch package maintenance
# 📎 Source: SOURCE_DIR is forwarded as GIT_SETUP_SOURCE_DIR to local tests

SOURCE_DIR ?= $(GIT_SETUP_SOURCE_DIR)

.PHONY: help-package build install reinstall clean test test-local test-automation update-upstream lint srcinfo-check

# ═══════════════════════════════════════════════════════════════
# 📚 HELP-PACKAGE - Show package workflow targets
# ═══════════════════════════════════════════════════════════════
help-package: ## Show package maintenance targets
	@printf "$(CYAN)Package maintenance targets$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  make build             Build the Arch package with makepkg -s\n"
	@printf "  make install           Build or reuse, then install with makepkg -si\n"
	@printf "  make reinstall         Cleanly rebuild and install with makepkg -Cfi\n"
	@printf "  make clean             Remove all local makepkg directories and artifacts\n"
	@printf "  make lint              Check Bash, ShellCheck, .SRCINFO, and whitespace\n"
	@printf "  make test-automation   Test upstream detection and metadata updates offline\n"
	@printf "  make update-upstream   Check upstream and update PKGBUILD/.SRCINFO locally\n"
	@printf "  make test-local SOURCE_DIR=/path/to/source\n"
	@printf "                         Build, install, and exercise committed local source\n"
	@printf "  make test SOURCE_DIR=/path/to/source\n"
	@printf "                         Run lint and package validations\n"
	@printf "  make srcinfo-check     Verify .SRCINFO matches PKGBUILD\n\n"

# ═══════════════════════════════════════════════════════════════
# 🏗️  BUILD - Create the Arch package without installing it
# ═══════════════════════════════════════════════════════════════
# ──── Build: Downloads sources, packages them, and leaves the artifact local ────
build: ## Build the Arch package
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🏗️  build · creating the Arch package$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@printf "  building with makepkg -s...\n\n"
	@makepkg -s
	@printf "$(GREEN)  ✓ package build completed$(NC)\n"
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • install the package:         $(BLUE)make install$(NC)\n"
	@printf "  • force a fresh rebuild:       $(BLUE)make reinstall$(NC)\n"
	@printf "  • remove build artifacts:      $(BLUE)make clean$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 📥 INSTALL - Build or reuse the package, then install it
# ═══════════════════════════════════════════════════════════════
# ──── Install: Uses makepkg -si and lets pacman install the package ────
install: ## Build or reuse, then install the package
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)📥 install · building or reusing the local package$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@printf "  running makepkg -si...\n\n"
	@makepkg -si
	@printf "$(GREEN)  ✓ git-setup is installed$(NC)\n"
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • start the interactive menu:  $(BLUE)git-setup$(NC)\n"
	@printf "  • remove generated artifacts:  $(BLUE)make clean$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🔄 REINSTALL - Force a clean build and installation
# ═══════════════════════════════════════════════════════════════
# ──── Reinstall: Clears work directories and rebuilds even if an artifact exists ────
reinstall: ## Force a clean rebuild and installation
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🔄 reinstall · forcing a clean package rebuild$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@printf "  running makepkg -Cfi...\n\n"
	@makepkg -Cfi
	@printf "$(GREEN)  ✓ fresh package build installed$(NC)\n"
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • start the interactive menu:  $(BLUE)git-setup$(NC)\n"
	@printf "  • validate the package:        $(BLUE)make test SOURCE_DIR=/path/to/source$(NC)\n"
	@printf "  • remove generated artifacts:  $(BLUE)make clean$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🧹 CLEAN - Remove generated makepkg state and artifacts
# ═══════════════════════════════════════════════════════════════
# ──── Clean: Removes only repository-local build directories and package files ────
clean: ## Remove all local makepkg directories and artifacts
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🧹 clean · removing local makepkg state and artifacts$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@printf "  removing src/, pkg/, source archives, and package artifacts...\n"
	@rm -rf -- src pkg
	@find . -maxdepth 1 -type f \( -name 'git-setup-*.pkg.tar.*' -o -name 'git-setup-*.tar.gz' \) -delete
	@printf "$(GREEN)  ✓ checkout is ready for a fresh package build$(NC)\n"
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • build the package:           $(BLUE)make build$(NC)\n"
	@printf "  • build and install it:        $(BLUE)make install$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🔎 LINT - Check package metadata and shell quality
# ═══════════════════════════════════════════════════════════════
# ──── Lint: Checks generated metadata, shell syntax, ShellCheck, and whitespace ────
lint: ## Check scripts, metadata, and whitespace
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🔎 lint · checking scripts, metadata, and whitespace$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@printf "  checking .SRCINFO against PKGBUILD...\n"
	@cmp .SRCINFO <(makepkg --printsrcinfo)
	@printf "  checking Bash syntax and ShellCheck...\n"
	@bash -n scripts/*.sh tests/*.sh tests/lib/*.sh
	@shellcheck scripts/*.sh tests/*.sh tests/lib/*.sh
	@printf "  checking whitespace errors...\n"
	@git diff --check
	@printf "$(GREEN)  ✓ lint passed$(NC)\n"
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • test package automation:    $(BLUE)make test-automation$(NC)\n"
	@printf "  • run every validation:        $(BLUE)make test SOURCE_DIR=/path/to/source$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🤖 TEST-AUTOMATION - Exercise upstream sync scripts without network access
# ═══════════════════════════════════════════════════════════════
test-automation: ## Test upstream package automation with local fixtures
	@tests/test-upstream-automation.sh

# ═══════════════════════════════════════════════════════════════
# 🔄 UPDATE-UPSTREAM - Apply the detected upstream release locally
# ═══════════════════════════════════════════════════════════════
update-upstream: ## Update package metadata from the latest stable upstream release
	@scripts/sync_upstream.sh

# ═══════════════════════════════════════════════════════════════
# 📄 SRCINFO-CHECK - Keep generated metadata in sync
# ═══════════════════════════════════════════════════════════════
# ──── Metadata: Compares the committed .SRCINFO with makepkg output ────
srcinfo-check: ## Verify .SRCINFO matches PKGBUILD
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)📄 srcinfo-check · comparing generated package metadata$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@cmp .SRCINFO <(makepkg --printsrcinfo)
	@printf "$(GREEN)  ✓ .SRCINFO matches PKGBUILD$(NC)\n"
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🧪 TEST-LOCAL - Build and exercise a local source revision
# ═══════════════════════════════════════════════════════════════
# ──── Local: Packages committed source HEAD and exercises the installed command ────
test-local: ## Validate a local source checkout in Docker
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🧪 test-local · validating a committed local source revision$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@test -n "$(SOURCE_DIR)" || { \
		printf '$(RED)ERROR: set SOURCE_DIR=/path/to/git-setup source checkout.$(NC)\n' >&2; \
		exit 2; \
	}
	@GIT_SETUP_SOURCE_DIR="$(SOURCE_DIR)" tests/validate-local-install.sh
	@printf "$(GREEN)  ✓ local package installation validation passed$(NC)\n"
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • run every validation:        $(BLUE)make test SOURCE_DIR=$(SOURCE_DIR)$(NC)\n"
	@printf "  • remove generated artifacts:  $(BLUE)make clean$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# ✅ TEST - Run every package validation
# ═══════════════════════════════════════════════════════════════
# ──── Test: Runs lint, automation, and local-install validations ────
test: ## Run every package validation
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)✅ test · running every package validation$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@$(MAKE) --no-print-directory lint EMBEDDED=1
	@$(MAKE) --no-print-directory test-automation EMBEDDED=1
	@$(MAKE) --no-print-directory test-local EMBEDDED=1 SOURCE_DIR="$(SOURCE_DIR)"
	@printf "$(GREEN)  ✓ all package validations passed$(NC)\n"
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • install the package:          $(BLUE)make install$(NC)\n"
	@printf "  • remove generated artifacts:   $(BLUE)make clean$(NC)\n\n"
endif
