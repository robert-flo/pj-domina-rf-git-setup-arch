#!/usr/bin/env bash

# Update PKGBUILD from release metadata emitted by check_upstream.sh. .SRCINFO
# remains generated output and is refreshed by the caller with makepkg.

set -Eeuo pipefail

readonly PKGBUILD_PATH="${PKGBUILD_PATH:-PKGBUILD}"
readonly UPSTREAM_VERSION="${UPSTREAM_VERSION:-}"
readonly ARCHIVE_SHA256="${ARCHIVE_SHA256:-}"
readonly OUTPUT_FILE="${GITHUB_OUTPUT:-}"

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

read_pkgbuild_value() {
  local name="$1"
  awk -F= -v name="$name" '$1 == name {print $2; exit}' "$PKGBUILD_PATH"
}

read_archive_checksum() {
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
  local current_pkgver current_pkgrel new_pkgrel updated_checksum
  local current_checksum

  [[ -f "$PKGBUILD_PATH" ]] || die "missing PKGBUILD: $PKGBUILD_PATH"
  [[ $UPSTREAM_VERSION =~ ^[0-9]+([.][0-9]+)*$ ]] \
    || die 'UPSTREAM_VERSION must be a stable numeric dotted version.'
  [[ $ARCHIVE_SHA256 =~ ^[[:xdigit:]]{64}$ ]] \
    || die 'ARCHIVE_SHA256 must contain exactly 64 hexadecimal characters.'

  current_pkgver="$(read_pkgbuild_value pkgver)"
  current_pkgrel="$(read_pkgbuild_value pkgrel)"
  current_checksum="$(read_archive_checksum)"
  [[ -n $current_pkgver ]] || die 'PKGBUILD does not define pkgver.'
  [[ $current_pkgrel =~ ^[0-9]+$ && $current_pkgrel -ge 1 ]] \
    || die 'PKGBUILD pkgrel must be a positive integer.'

  # Con el contrato nuevo de pipeline (tarball al vuelo desde dispatch con SKIP),
  # no se debe mutar el PKGBUILD ni pisar el SKIP bajo ninguna circunstancia.
  if [[ $current_checksum == "SKIP" ]]; then
    printf 'PKGBUILD uses dynamic pipeline archive (SKIP); preserving contract without modification.\n'
    write_output pkgver "$current_pkgver"
    write_output pkgrel "$current_pkgrel"
    return 0
  fi

  if [[ $UPSTREAM_VERSION == "$current_pkgver" ]]; then
    new_pkgrel=$((current_pkgrel + 1))
  else
    new_pkgrel=1
  fi

  sed -Ei "s/^pkgver=.*/pkgver=${UPSTREAM_VERSION}/" "$PKGBUILD_PATH"
  sed -Ei "s/^pkgrel=.*/pkgrel=${new_pkgrel}/" "$PKGBUILD_PATH"
  sed -Ei \
    "/^sha256sums=\(/,/^\)/{0,/^[[:space:]]*'[^']*'[[:space:]]*$/{s//  '${ARCHIVE_SHA256}'/}}" \
    "$PKGBUILD_PATH"

  updated_checksum="$(read_archive_checksum)"
  [[ $(read_pkgbuild_value pkgver) == "$UPSTREAM_VERSION" ]] \
    || die 'failed to update pkgver in PKGBUILD.'
  [[ $(read_pkgbuild_value pkgrel) == "$new_pkgrel" ]] \
    || die 'failed to update pkgrel in PKGBUILD.'
  [[ $updated_checksum == "$ARCHIVE_SHA256" ]] \
    || die 'failed to update the release archive checksum in PKGBUILD.'

  write_output pkgver "$UPSTREAM_VERSION"
  write_output pkgrel "$new_pkgrel"
}

main "$@"
