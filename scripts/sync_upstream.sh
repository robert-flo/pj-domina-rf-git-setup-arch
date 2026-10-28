#!/usr/bin/env bash

# Run the local portion of the scheduled workflow: detect a new stable release,
# update PKGBUILD, and regenerate .SRCINFO. It never builds, commits, or pushes.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PACKAGE_DIR

state_dir=""

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

read_state() {
  local name="$1"
  awk -F= -v name="$name" '$1 == name {print substr($0, length(name) + 2); exit}' \
    "$state_dir/check-output"
}

main() {
  local changed upstream_version archive_sha256

  cd "$PACKAGE_DIR"
  state_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-setup-upstream-sync.XXXXXX")"
  trap 'rm -rf "$state_dir"' EXIT

  printf '==> Checking the latest stable upstream release\n'
  GITHUB_OUTPUT="$state_dir/check-output" "$SCRIPT_DIR/check_upstream.sh"

  changed="$(read_state changed)"
  [[ -n $changed ]] || die 'check_upstream.sh did not report whether metadata changed.'

  if [[ $changed != true ]]; then
    printf '\nNo update: PKGBUILD already matches upstream.\n'
    exit 0
  fi

  upstream_version="$(read_state upstream_version)"
  archive_sha256="$(read_state archive_sha256)"
  [[ -n $upstream_version && -n $archive_sha256 ]] \
    || die 'check_upstream.sh did not report complete release metadata.'

  printf '\n==> Updating PKGBUILD and regenerating .SRCINFO\n'
  UPSTREAM_VERSION="$upstream_version" ARCHIVE_SHA256="$archive_sha256" \
    "$SCRIPT_DIR/update_package.sh"
  makepkg --printsrcinfo > .SRCINFO

  printf '\nUpdated package metadata. Review with: git diff -- PKGBUILD .SRCINFO\n'
  printf 'Then validate with: make build\n'
}

main "$@"
