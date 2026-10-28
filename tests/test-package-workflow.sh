#!/usr/bin/env bash
# shellcheck disable=SC2016

# Network-free contract tests for the on-the-fly packaging workflow:
# package.yml structure, the PKGBUILD contract, .SRCINFO consistency, and
# the version/tarball derivation run against local git fixtures.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PACKAGE_DIR
readonly WORKFLOW="$PACKAGE_DIR/.github/workflows/package.yml"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/package-workflow-test.XXXXXX")"
readonly TEST_ROOT

trap 'rm -rf "$TEST_ROOT"' EXIT

die() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

have() {
  grep -qF -- "$1" "$WORKFLOW" || die "package.yml is missing: $1"
}

miss() {
  ! grep -qF -- "$1" "$2" || die "$3"
}

# The run body of a named step, extracted from the YAML and dedented: this
# is the logic the workflow will execute, tested directly instead of trusted.
extract_run() {
  awk -v step="$1" '
    $0 == "      - name: " step { found_step = 1; next }
    found_step && /^        run: \|/ { in_run = 1; next }
    in_run {
      if ($0 ~ /^ {10}/) { sub(/^ {10}/, ""); print; next }
      if ($0 ~ /^[[:space:]]*$/) { next }
      exit
    }
  ' "$WORKFLOW"
}

# package.yml structure: dispatch trigger, Arch container, checkout at the
# payload sha, git archive of that sha, install test, artifact upload.
have 'repository_dispatch:'
have 'Checkout this package repository'
have 'source-updated'
have 'image: archlinux:base'
have 'repository: ${{ steps.source.outputs.repo }}'
have 'ref: ${{ steps.source.outputs.sha }}'
have 'fetch-depth: 0'
have 'archive --format=tar.gz'
have 'pj-domina-rf-git-setup-${pkgver}/'
have 'pacman -U --noconfirm'
have '/usr/bin/git-setup'
have '/opt/git-setup/git-setup'
have '/usr/share/applications/git-setup.desktop'
have 'actions/upload-artifact@v4'
have 'path: build/*.pkg.tar.zst'
have 'if-no-files-found: error'

# El orden importa: archlinux:base no trae git ni makepkg, así que las
# dependencias se instalan antes del primer paso que los usa.
deps_line="$(grep -n '      - name: Install build and runtime dependencies' "$WORKFLOW" | cut -d: -f1)"
version_line="$(grep -n '      - name: Compute the trackable version and generate the tarball' "$WORKFLOW" | cut -d: -f1)"
[[ -n "$deps_line" && -n "$version_line" && "$deps_line" -lt "$version_line" ]] || \
  die 'the dependency install step must come before the version step (the base image has no git)'

# PKGBUILD contract: the tag tarball and its fixed checksum are gone, the
# generated tarball enters as a local source with SKIP, the launcher keeps
# its real checksum, and the version comes from PKGVER.
miss 'archive/refs/tags' "$PACKAGE_DIR/PKGBUILD" 'PKGBUILD still references the tag tarball'
grep -qF 'pkgver="${PKGVER:-0.2.0}"' "$PACKAGE_DIR/PKGBUILD" || \
  die 'PKGBUILD does not take the version from PKGVER'
grep -qF '${pkgname}-${pkgver}.tar.gz' "$PACKAGE_DIR/PKGBUILD" || \
  die 'PKGBUILD does not declare the generated tarball as a local source'
grep -qF "'SKIP'" "$PACKAGE_DIR/PKGBUILD" || \
  die 'PKGBUILD does not skip the checksum of the generated tarball'
grep -qF 'e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150' "$PACKAGE_DIR/PKGBUILD" || \
  die 'PKGBUILD lost the launcher checksum'
grep -qF 'source_dir="${srcdir}/pj-domina-rf-git-setup-${pkgver}"' "$PACKAGE_DIR/PKGBUILD" || \
  die 'package() no longer matches the tarball layout'

# .SRCINFO is regenerated to the same contract.
miss 'archive/refs/tags' "$PACKAGE_DIR/.SRCINFO" '.SRCINFO still references the tag tarball'
grep -qE '^	pkgver = 0\.2\.0$' "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO pkgver is not the 0.2.0 base'
grep -qE '^	source = git-setup-0\.2\.0\.tar\.gz$' "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO missing the generated tarball source'
grep -qE '^	source = git-setup$' "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO missing the launcher source'
grep -qE '^	sha256sums = SKIP$' "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO does not skip the tarball checksum'
grep -qE '^	sha256sums = e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150$' "$PACKAGE_DIR/.SRCINFO" || \
  die '.SRCINFO lost the launcher checksum'

# Version derivation against real git fixtures.
version_script="$TEST_ROOT/version.sh"
extract_run 'Compute the trackable version and generate the tarball' > "$version_script"
[[ -s "$version_script" ]] || die 'could not extract the version step from package.yml'
bash -n "$version_script" || die 'the extracted version step is not valid bash'

make_fixture() { # make_fixture <name> <commits> <tag?>
  local repo="$TEST_ROOT/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name 'Fixture'
  git -C "$repo" config user.email fixture@example.test
  for _ in $(seq 1 "$2"); do
    printf '%s\n' "$RANDOM" > "$repo/file"
    git -C "$repo" add file
    git -C "$repo" commit -qm 'fixture commit'
  done
  if [[ -n ${3:-} ]]; then
    git -C "$repo" tag "$3" HEAD~3 2>/dev/null || git -C "$repo" tag "$3" HEAD
  fi
  printf '%s\n' "$repo"
}

run_version() { # run_version <fixture repo> -> echoes "pkgver sha"
  local out="$TEST_ROOT/gh-output" build="$TEST_ROOT/build"
  rm -rf "$out" "$build"
  SRC_DIR="$1" REF_SHA='' PKG_BUILD="$build" GITHUB_OUTPUT="$out" \
    bash "$version_script" >"$TEST_ROOT/version.log" 2>&1
  printf '%s %s\n' "$(sed -n 's/^pkgver=//p' "$out")" "$(sed -n 's/^sha=//p' "$out")"
}

# Tagged fixture: tag v0.2.0 two commits back, three commits after the tag.
tagged="$(make_fixture tagged 5 'v0.2.0')"
read -r pkgver sha <<<"$(run_version "$tagged")"
expected="0.2.0.r3.$(git -C "$tagged" rev-parse --short=7 HEAD)"
[[ $pkgver == "$expected" ]] || die "tagged fixture: expected $expected, got $pkgver"
[[ $sha == "$(git -C "$tagged" rev-parse HEAD)" ]] || die 'the reported sha is not the packaged commit'
tarball="$TEST_ROOT/build/git-setup-${pkgver}.tar.gz"
[[ -s "$tarball" ]] || die "the tarball was not generated: $tarball"
tar -tzf "$tarball" | head -1 | grep -qF "pj-domina-rf-git-setup-${pkgver}/" || \
  die 'the tarball root does not match the package() layout'

# Untagged fixture: no tags, so N is the total number of commits.
untagged="$(make_fixture untagged 2)"
read -r pkgver sha <<<"$(run_version "$untagged")"
expected="0.2.0.r2.$(git -C "$untagged" rev-parse --short=7 HEAD)"
[[ $pkgver == "$expected" ]] || die "untagged fixture: expected $expected, got $pkgver"

# The build and install step is syntactically valid.
build_script="$TEST_ROOT/build.sh"
extract_run 'Build the package and install-test it' > "$build_script"
[[ -s "$build_script" ]] || die 'could not extract the build step from package.yml'
bash -n "$build_script" || die 'the extracted build step is not valid bash'

printf '%s\n' 'ok package-workflow'
