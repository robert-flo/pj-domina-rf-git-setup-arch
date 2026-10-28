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
have 'runtime/helper runtime/lib'
have '/opt/git-setup/runtime/commands.tsv'
have 'runtime/completion'
have '/usr/bin/git-setup help'
have '/opt/git-setup/git-setup help'
have 'default: ${{ github.repository }}'
have '${GITHUB_REPOSITORY%-arch}'
have 'actions/upload-artifact@v4'
have 'path: build/*.pkg.tar.zst'
have 'if-no-files-found: error'

# El orden importa: archlinux:base no trae git ni makepkg, así que las
# dependencias se instalan antes del primer paso que los usa.
deps_line="$(grep -n '      - name: Install build and runtime dependencies' "$WORKFLOW" | cut -d: -f1)"
version_line="$(grep -n '      - name: Compute the trackable version and generate the tarball' "$WORKFLOW" | cut -d: -f1)"
[[ -n "$deps_line" && -n "$version_line" && "$deps_line" -lt "$version_line" ]] || \
  die 'the dependency install step must come before the version step (the base image has no git)'
checkout_line="$(grep -n '      - name: Checkout the source at the dispatched commit' "$WORKFLOW" | cut -d: -f1)"
[[ -n "$checkout_line" && "$deps_line" -lt "$checkout_line" ]] || \
  die 'the dependency install step must come before the source checkout (the REST fallback leaves no history)'

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
grep -qE '^\tpkgver = 0\.2\.0$' "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO pkgver is not the 0.2.0 base'
grep -qE '^\tsource = git-setup-0\.2\.0\.tar\.gz$' "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO missing the generated tarball source'
grep -qE '^\tsource = git-setup$' "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO missing the launcher source'
grep -qE '^\tsha256sums = SKIP$' "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO does not skip the tarball checksum'
grep -qE '^\tsha256sums = e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150$' "$PACKAGE_DIR/.SRCINFO" || \
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

# ---------------------------------------------------------------------- #
# Default del input repo: con owner y sin el sufijo -arch.                #
# ---------------------------------------------------------------------- #
resolve_script="$TEST_ROOT/resolve.sh"
extract_run 'Resolve the dispatched source' > "$resolve_script"
[[ -s "$resolve_script" ]] || die 'could not extract the resolve step from package.yml'
bash -n "$resolve_script" || die 'the extracted resolve step is not valid bash'

expect_fail() { # expect_fail <por que debe fallar> <cmd...>
  local why="$1"; shift
  # En subshell: die del check hace exit y no debe matar el test entero.
  if ( "$@" ) > /dev/null 2>&1; then
    die "la mutación no fue detectada: $why"
  fi
}

check_ownerful() { # check_ownerful <github_output_file> <why>
  local repo
  repo="$(sed -n 's/^repo=//p' "$1")"
  [[ $repo == */* ]] || die "el default del input repo no lleva owner ($2): '$repo'"
  [[ $repo != *-arch ]] || die "el default del input repo arrastra el sufijo -arch ($2): '$repo'"
}

run_resolve() { # run_resolve <script> <env...> -> imprime repo resuelto
  local script="$1"; shift
  local out="$TEST_ROOT/resolve-output"
  rm -f "$out"
  env -u DISPATCH_REPO -u DISPATCH_SHA -u INPUT_REPO -u INPUT_SHA \
    "$@" GITHUB_OUTPUT="$out" GITHUB_REPOSITORY='robert-flo/pj-domina-rf-git-setup-arch' \
    bash "$script"
  printf '%s\n' "$(sed -n 's/^repo=//p' "$out")"
}

# workflow_dispatch con defaults: el input vale este repo (con -arch) y el
# paso lo reduce a la fuente con owner.
resolved="$(run_resolve "$resolve_script" INPUT_REPO='robert-flo/pj-domina-rf-git-setup-arch')"
[[ $resolved == 'robert-flo/pj-domina-rf-git-setup' ]] || \
  die "workflow_dispatch con defaults resolvio '$resolved', esperaba la fuente con owner"
check_ownerful "$TEST_ROOT/resolve-output" 'dispatch con defaults'

# repository_dispatch manda su propio repo y el paso no lo toca.
resolved="$(run_resolve "$resolve_script" DISPATCH_REPO='octocat/otra-fuente')"
[[ $resolved == 'octocat/otra-fuente' ]] || die "repository_dispatch altero el repo despachado: $resolved"

# repository_dispatch sin payload: cae al default derivado, con owner.
resolved="$(run_resolve "$resolve_script")"
[[ $resolved == 'robert-flo/pj-domina-rf-git-setup' ]] || \
  die "dispatch sin payload resolvio '$resolved', esperaba la fuente con owner"

# Mutación: el default viejo hardcodeado sin owner debe morir en el check.
old_resolve="$TEST_ROOT/resolve-old.sh"
cat > "$old_resolve" <<'OLD_RESOLVE'
repo="${DISPATCH_REPO:-${INPUT_REPO:-pj-domina-rf-git-setup}}"
sha="${DISPATCH_SHA:-${INPUT_SHA:-}}"
{
  printf 'repo=%s\n' "$repo"
  printf 'sha=%s\n' "$sha"
} >> "$GITHUB_OUTPUT"
OLD_RESOLVE
resolved="$(run_resolve "$old_resolve")"
[[ $resolved == 'pj-domina-rf-git-setup' ]] || die "el fixture de la mutación no reproduce el bug: $resolved"
expect_fail 'default sin owner' check_ownerful "$TEST_ROOT/resolve-output" 'default viejo hardcodeado'

# ---------------------------------------------------------------------- #
# package() funciona: contra un fixture del árbol fuente se ejecuta el    #
# package() real del PKGBUILD y se fuma el payload instalado.             #
# ---------------------------------------------------------------------- #
run_package() { # run_package <pkgbuild> <pkgdir>
  (
    set -Eeuo pipefail
    local pkgver=0.2.0 srcdir="$TEST_ROOT/pkg-src" pkgdir="$2"
    rm -rf "$pkgdir"
    mkdir -p "$srcdir"
    cp "$PACKAGE_DIR/git-setup" "$srcdir/git-setup"
    # shellcheck disable=SC1090
    source "$1"
    package
  )
}

check_installed() { # check_installed <pkgdir>
  local payload="$1/opt/git-setup" subdir out
  [[ -x $1/usr/bin/git-setup ]] || return 1
  [[ -x $payload/git-setup ]] || return 1
  for subdir in runtime/helper runtime/lib runtime/scripts runtime/templates/git runtime/completion; do
    [[ -d $payload/$subdir && -n "$(ls -A "$payload/$subdir")" ]] || return 1
  done
  [[ -f $payload/runtime/commands.tsv ]] || return 1
  # Smoke sin estado. /usr/bin/git-setup es el wrapper que hace exec del
  # launcher de /opt con ruta absoluta, así que en el sandbox (sin /opt)
  # se verifica su exec y se corre el launcher del payload, que es
  # exactamente a lo que apunta; el run real fuma ambos entrypoints.
  grep -qF 'exec /opt/git-setup/git-setup' "$1/usr/bin/git-setup" || return 1
  out="$("$payload/git-setup")" || return 1
  [[ $out == "runtime resuelto: $payload/runtime" ]] || return 1
}

# Fixture del árbol fuente en el layout real (launcher en el raiz, todo el
# runtime bajo runtime/), con un launcher espejo del contrato de resolución
# del launcher verdadero: scrDir/runtime sin fallback.
pkgsrc="$TEST_ROOT/pkg-src"
source_dir_fixture="$pkgsrc/pj-domina-rf-git-setup-0.2.0"
mkdir -p "$source_dir_fixture/runtime/helper" "$source_dir_fixture/runtime/lib" \
  "$source_dir_fixture/runtime/scripts" "$source_dir_fixture/runtime/templates/git" \
  "$source_dir_fixture/runtime/completion"
cat > "$source_dir_fixture/git-setup" <<'FIXTURE_LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail
# Espejo del contrato de resolución del launcher real (git-setup de la
# fuente): scrDir/runtime sin fallback, y el proyecto vive en el runtime
# que set_variable fija.
scrDir="$(dirname "$(realpath "$0")")"
RUNTIME_DIR="$scrDir/runtime"
source "$RUNTIME_DIR/helper/set_variable.sh"
PROJECT_DIR="$GIT_SETUP_RUNTIME_DIR"
source "$PROJECT_DIR/lib/presentation.sh"
printf 'runtime resuelto: %s\n' "$PROJECT_DIR"
FIXTURE_LAUNCHER
printf 'readonly GIT_SETUP_RUNTIME_DIR="${GIT_SETUP_RUNTIME_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"\n' \
  > "$source_dir_fixture/runtime/helper/set_variable.sh"
printf '# stub del runtime para el fixture del paquete\n' \
  > "$source_dir_fixture/runtime/lib/presentation.sh"
printf '#!/usr/bin/env bash\ntrue\n' > "$source_dir_fixture/runtime/scripts/help"
printf 'stub\n' > "$source_dir_fixture/runtime/templates/git/gitconfig"
printf 'stub\n' > "$source_dir_fixture/runtime/commands.tsv"
printf 'stub\n' > "$source_dir_fixture/runtime/completion/git-setup.bash"
printf 'stub\n' > "$source_dir_fixture/runtime/completion/_git-setup"

# El package() consume el arbol del repo fuente: cada ruta que referencia
# debe existir alla. Si la fuente mueve el runtime, la asercion avisa antes
# del run real.
while IFS= read -r ref; do
  rel="${ref#\$\{source_dir\}/}"
  rel="${rel%/}"
  [[ -n "$rel" && -e "$source_dir_fixture/$rel" ]] || \
    die "package() references a source path missing from the source tree: $ref"
done < <(grep -oE '"\$\{source_dir\}/[^"]+"' "$PACKAGE_DIR/PKGBUILD" | tr -d '"')

good_pkgbuild="$TEST_ROOT/PKGBUILD.good"
cp "$PACKAGE_DIR/PKGBUILD" "$good_pkgbuild"
run_package "$good_pkgbuild" "$TEST_ROOT/pkg-good"
check_installed "$TEST_ROOT/pkg-good" || die 'el payload instalado no corre el launcher (caso bueno)'

# Mutación: payload sin commands.tsv debe morir en el check.
sed '/install -Dm644 "${source_dir}\/runtime\/commands.tsv"/d' "$good_pkgbuild" \
  > "$TEST_ROOT/PKGBUILD.no-catalog"
run_package "$TEST_ROOT/PKGBUILD.no-catalog" "$TEST_ROOT/pkg-no-catalog"
expect_fail 'payload sin commands.tsv' check_installed "$TEST_ROOT/pkg-no-catalog"

# Mutación: payload sin el runtime anidado debe morir en el check.
sed 's|${payload_dir}/runtime|${payload_dir}|g' "$good_pkgbuild" \
  > "$TEST_ROOT/PKGBUILD.flat"
run_package "$TEST_ROOT/PKGBUILD.flat" "$TEST_ROOT/pkg-flat"
expect_fail 'payload sin runtime/' check_installed "$TEST_ROOT/pkg-flat"

# El PKGBUILD declara el catálogo y la completion en el payload.
grep -qF 'runtime/commands.tsv' "$PACKAGE_DIR/PKGBUILD" || \
  die 'PKGBUILD does not ship runtime/commands.tsv in the payload'
grep -qF 'runtime/completion' "$PACKAGE_DIR/PKGBUILD" || \
  die 'PKGBUILD does not ship runtime/completion in the payload'

printf '%s\n' 'ok package-workflow'
