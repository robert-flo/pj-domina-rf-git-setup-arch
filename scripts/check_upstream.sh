#!/usr/bin/env bash

# Resolve the latest stable upstream release and compare its generated source
# archive with the version and checksum currently pinned in PKGBUILD.

set -Eeuo pipefail

readonly UPSTREAM_REPO="${UPSTREAM_REPO:-robert-flo/PJ-DOMINA-rf-git-setup}"
readonly PKGBUILD_PATH="${PKGBUILD_PATH:-PKGBUILD}"
readonly OUTPUT_FILE="${GITHUB_OUTPUT:-}"

download_dir=""

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" > /dev/null 2>&1 || die "$1 is required."
}

read_current_pkgver() {
  awk -F= '/^pkgver=/{print $2; exit}' "$PKGBUILD_PATH"
}

read_current_archive_checksum() {
  awk -F "'" '
    /^sha256sums=\(/ { in_checksums = 1 }
    in_checksums {
      for (field = 2; field <= NF; field += 2) {
        print $field
        exit
      }
    }
  ' "$PKGBUILD_PATH"
}

write_output() {
  local name="$1"
  local value="$2"

  printf '%s=%s\n' "$name" "$value"
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s=%s\n' "$name" "$value" >> "$OUTPUT_FILE"
  fi
}

main() {
  local release_json upstream_tag upstream_version archive_url
  local current_pkgver current_checksum archive_checksum changed
  local archive_path

  require_command gh
  require_command jq
  require_command curl
  require_command sha256sum
  [[ -f "$PKGBUILD_PATH" ]] || die "missing PKGBUILD: $PKGBUILD_PATH"

  release_json="$(gh api "repos/$UPSTREAM_REPO/releases/latest")"
  upstream_tag="$(jq -r '.tag_name // empty' <<< "$release_json")"
  [[ $upstream_tag =~ ^v([0-9]+([.][0-9]+)*)$ ]] \
    || die "latest upstream release tag is not a stable vN.N version: ${upstream_tag:-<empty>}"
  upstream_version="${BASH_REMATCH[1]}"

  archive_url="https://github.com/${UPSTREAM_REPO}/archive/refs/tags/${upstream_tag}.tar.gz"
  download_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-setup-upstream.XXXXXX")"
  trap 'rm -rf "$download_dir"' EXIT
  archive_path="$download_dir/git-setup-${upstream_version}.tar.gz"

  curl --fail --location --silent --show-error \
    --retry 3 --retry-delay 2 \
    "$archive_url" --output "$archive_path"
  archive_checksum="$(sha256sum "$archive_path" | awk '{print $1}')"
  [[ $archive_checksum =~ ^[[:xdigit:]]{64}$ ]] \
    || die 'failed to calculate a valid SHA-256 checksum for the upstream archive.'

  current_pkgver="$(read_current_pkgver)"
  current_checksum="$(read_current_archive_checksum)"
  [[ -n $current_pkgver ]] || die "PKGBUILD does not define pkgver: $PKGBUILD_PATH"

  changed=false
  if [[ $upstream_version != "$current_pkgver" || $archive_checksum != "$current_checksum" ]]; then
    changed=true
  fi

  write_output changed "$changed"
  write_output upstream_tag "$upstream_tag"
  write_output upstream_version "$upstream_version"
  write_output archive_url "$archive_url"
  write_output archive_sha256 "$archive_checksum"
  write_output current_pkgver "$current_pkgver"
  write_output current_archive_sha256 "$current_checksum"
}

main "$@"
