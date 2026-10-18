#!/usr/bin/env bash

# End-to-end validation for a local git-setup source checkout.
#
# The script creates a release-shaped archive from the checkout's committed
# HEAD, builds and installs the Arch package in a disposable container, and
# exercises the installed public command. It never installs packages on the
# host and never mounts the host HOME directory.
#
# Important: `git archive HEAD` excludes staged, unstaged, ignored, and
# untracked source files. Commit source changes before running this validation.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PACKAGE_DIR
readonly CONTAINER_SCRIPT="$SCRIPT_DIR/lib/container-validate.sh"
PKG_VERSION="$(awk -F= '/^pkgver=/{print $2; exit}' "$PACKAGE_DIR/PKGBUILD")"
readonly PKG_VERSION
readonly PKG_ARCHIVE_PREFIX="PJ-DOMINA-rf-git-setup-${PKG_VERSION}/"

# shellcheck disable=SC1091 # The library path is derived from this script's location.
source "$SCRIPT_DIR/lib/host-checks.sh"

# Populated by validate_source_dir.
source_dir="${GIT_SETUP_SOURCE_DIR:-}"
source_commit=""
archive_dir=""
archive_path=""

usage() {
  cat <<'USAGE'
Usage:
  GIT_SETUP_SOURCE_DIR=/path/to/git-setup \
    tests/validate-local-install.sh

Purpose:
  Build the package from a local source checkout, install it in a disposable
  Arch Linux container, and exercise the installed public git-setup command.

Required input:
  GIT_SETUP_SOURCE_DIR
    Path to the separate git-setup source-repository checkout. The directory
    must be a Git worktree and contain the root ./git-setup dispatcher.

Source snapshot rule:
  The test uses `git archive HEAD`, so it validates committed source files only.
  Staged, unstaged, ignored, and untracked source files are not included.

Container phases (see lib/container-validate.sh):
  1. Refresh Arch and install the current package's exact prerequisites.
  2. Create an unprivileged builder account for makepkg.
  3. Build and install the package from the temporary local archive.
  4. Check the launcher, installed payload, and public commands.

Packages installed inside the container:
  fakeroot
    Required by makepkg to create a package as an unprivileged user.
  sudo
    Lets the builder invoke pacman for `makepkg -i`.
  git, github-cli, gnupg, openssh, git-delta
    Runtime dependencies declared by PKGBUILD and exercised by git-setup.

Why base-devel is not installed:
  git-setup is a Bash-only `arch=('any')` package with no compilation step.
  archlinux:latest already supplies makepkg and the basic archive utilities.
  PKGBUILD disables debug packages because shell scripts contain no native debug
  symbols. If native compilation is introduced, restore a full base-devel build
  environment and update this explanation.

Host impact:
  - No host packages are installed or upgraded.
  - No host HOME, Git configuration, SSH keys, or GPG keys are mounted.
  - Package files and the temporary archive are mounted read-only.
  - The temporary archive is removed when the script exits.
  - Docker may pull/cache archlinux:latest and use bandwidth and disk space.
  - `docker run --rm` deletes the container and its installed packages on exit.

Checksum behavior:
  The generated local archive is not byte-identical to GitHub's release archive,
  so this test redirects PKGBUILD to the local file and uses --skipchecksums.
  validate-release-archive.sh independently verifies the published checksums.

Exit status:
  0  Package installation and all public-command checks passed.
  2  Usage, host dependency, or source-checkout configuration error.
  *  Docker, pacman, makepkg, installation, or a command assertion failed.
USAGE
}

check_host_deps() {
  command -v git > /dev/null 2>&1 || die 'git is required on the host to create the source archive.'
  require_docker
  [[ -f "$CONTAINER_SCRIPT" ]] || die "missing companion script: $CONTAINER_SCRIPT"
  [[ $PKG_VERSION =~ ^[0-9]+([.][0-9]+)*$ ]] || die 'PKGBUILD contains an invalid pkgver.'
}

validate_source_dir() {
  if [[ -z "$source_dir" || ! -d "$source_dir" || ! -f "$source_dir/git-setup" ]]; then
    printf '%s\n\n' 'ERROR: Set GIT_SETUP_SOURCE_DIR to a git-setup source checkout.' >&2
    usage >&2
    exit 2
  fi

  if [[ $(git -C "$source_dir" rev-parse --is-inside-work-tree 2> /dev/null) != true ]]; then
    die "GIT_SETUP_SOURCE_DIR is not a Git worktree: $source_dir"
  fi

  source_dir="$(cd "$source_dir" && pwd)"
  source_commit="$(git -C "$source_dir" rev-parse --short HEAD)"
}

setup_archive_workspace() {
  archive_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-setup-package.XXXXXX")"
  trap 'rm -rf "$archive_dir"' EXIT
  chmod 0755 "$archive_dir"
  archive_path="$archive_dir/git-setup-${PKG_VERSION}.tar.gz"
}

print_plan() {
  cat <<PLAN
Local package installation validation
-------------------------------------
Source checkout: $source_dir
Source commit:   $source_commit (committed HEAD only)
Package files:   $PACKAGE_DIR
Container:       archlinux:latest (ephemeral)

The following pacman transaction occurs inside the container, not on the host.
It installs only fakeroot, sudo, and git-setup's runtime dependencies.
PLAN
}

build_source_archive() {
  printf '\n==> [host 1/2] Creating the temporary source archive\n'
  git -C "$source_dir" archive --format=tar.gz \
    --prefix="$PKG_ARCHIVE_PREFIX" \
    HEAD > "$archive_path"
}

run_container_validation() {
  printf '==> [host 2/2] Starting the disposable Arch Linux container\n'
  docker run --rm \
    --volume "$PACKAGE_DIR:/package:ro" \
    --volume "$archive_dir:/archive:ro" \
    --volume "$CONTAINER_SCRIPT:/container-validate.sh:ro" \
    --env "PKG_VERSION=$PKG_VERSION" \
    archlinux:latest \
    bash /container-validate.sh
}

main() {
  parse_help_arg "$@"
  check_host_deps
  validate_source_dir
  setup_archive_workspace
  print_plan
  build_source_archive
  run_container_validation
  printf '\nPASS: local package validation succeeded — build, installation, launcher, payload, and all validated public commands behaved as expected.\n\n'
}

main "$@"
