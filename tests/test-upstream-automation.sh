#!/usr/bin/env bash

# Fast, network-free contract tests for the upstream package automation.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PACKAGE_DIR

test_dir=""

die() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_line() {
  local expected="$1"
  local path="$2"
  grep -Fxq "$expected" "$path" || die "missing '$expected' in $path"
}

expect_fail() {
  local why="$1"; shift
  if ( "$@" ) > /dev/null 2>&1; then
    die "la mutación no fue detectada: $why"
  fi
}

check_pkgbuild_preserves_skip() {
  local path="$1"
  grep -Fxq "  'SKIP'" "$path" || die "missing '  'SKIP'' in $path"
}

setup() {
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-setup-automation-test.XXXXXX")"
  trap 'rm -rf "$test_dir"' EXIT
  mkdir -p "$test_dir/bin"
  cp "$PACKAGE_DIR/PKGBUILD" "$test_dir/PKGBUILD"

  cat > "$test_dir/bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' '{"tag_name":"v9.8.7"}'
MOCK_GH

  cat > "$test_dir/bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
output=""
while (($#)); do
  if [[ $1 == --output ]]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
[[ -n $output ]]
printf '%s\n' 'deterministic upstream archive fixture' > "$output"
MOCK_CURL

  chmod +x "$test_dir/bin/gh" "$test_dir/bin/curl"
}

test_check_reports_unchanged_when_pkgbuild_uses_skip() {
  local output_file="$test_dir/check-output"
  local expected_checksum

  expected_checksum="$(printf '%s\n' 'deterministic upstream archive fixture' | sha256sum | awk '{print $1}')"
  PATH="$test_dir/bin:$PATH" \
    PKGBUILD_PATH="$test_dir/PKGBUILD" \
    GITHUB_OUTPUT="$output_file" \
    "$PACKAGE_DIR/scripts/check_upstream.sh" > /dev/null

  assert_file_line 'changed=false' "$output_file"
  assert_file_line 'upstream_tag=v9.8.7' "$output_file"
  assert_file_line 'upstream_version=9.8.7' "$output_file"
  assert_file_line "archive_sha256=$expected_checksum" "$output_file"
  assert_file_line 'current_archive_sha256=SKIP' "$output_file"
}

test_update_preserves_skip_contract() {
  local checksum
  checksum="$(printf '%s\n' 'deterministic upstream archive fixture' | sha256sum | awk '{print $1}')"

  cp "$test_dir/PKGBUILD" "$test_dir/PKGBUILD.before"

  PKGBUILD_PATH="$test_dir/PKGBUILD" \
    UPSTREAM_VERSION=9.8.7 \
    ARCHIVE_SHA256="$checksum" \
    "$PACKAGE_DIR/scripts/update_package.sh" > /dev/null

  check_pkgbuild_preserves_skip "$test_dir/PKGBUILD"
  cmp -s "$test_dir/PKGBUILD" "$test_dir/PKGBUILD.before" \
    || die 'update_package.sh modificó PKGBUILD a pesar del contrato SKIP'
}

test_revived_flow_overwriting_skip_fails() {
  local checksum
  checksum="$(printf '%s\n' 'deterministic upstream archive fixture' | sha256sum | awk '{print $1}')"
  local mutated="$test_dir/PKGBUILD.revived"

  # Simula el flujo viejo revivido pisando SKIP con el checksum fijo del release
  sed "s/'SKIP'/'${checksum}'/" "$test_dir/PKGBUILD" > "$mutated"

  expect_fail 'flujo revivido pisa SKIP con checksum fijo' check_pkgbuild_preserves_skip "$mutated"
}

main() {
  setup
  test_check_reports_unchanged_when_pkgbuild_uses_skip
  test_update_preserves_skip_contract
  test_revived_flow_overwriting_skip_fails
  printf 'PASS: upstream automation contracts\n'
}

main "$@"
