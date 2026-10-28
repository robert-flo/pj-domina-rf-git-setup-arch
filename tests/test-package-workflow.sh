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

# .SRCINFO is regenerated to the same contract. El .SRCINFO sangra con
# tab: el patrón genera el tab con $'\t' para no depender de un tab
# literal en este archivo.
miss 'archive/refs/tags' "$PACKAGE_DIR/.SRCINFO" '.SRCINFO still references the tag tarball'
srcinfo_lead=$'\t'
grep -qE "^${srcinfo_lead}pkgver = 0\.2\.0$" "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO pkgver is not the 0.2.0 base'
grep -qE "^${srcinfo_lead}source = git-setup-0\.2\.0\.tar\.gz$" "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO missing the generated tarball source'
grep -qE "^${srcinfo_lead}source = git-setup$" "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO missing the launcher source'
grep -qE "^${srcinfo_lead}sha256sums = SKIP$" "$PACKAGE_DIR/.SRCINFO" || die '.SRCINFO does not skip the tarball checksum'
grep -qE "^${srcinfo_lead}sha256sums = e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150$" "$PACKAGE_DIR/.SRCINFO" || \
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
# El listing va a un archivo: tar | head -1 con pipefail muere por SIGPIPE
# de forma esporádica cuando head cierra el pipe antes de que tar termine.
tar -tzf "$tarball" > "$TEST_ROOT/tarball.listing" 2>/dev/null
head -1 "$TEST_ROOT/tarball.listing" | grep -qF "pj-domina-rf-git-setup-${pkgver}/" || \
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

# ---------------------------------------------------------------------- #
# Publicación en la nube (ticket 3): el paquete entra al canal stable de  #
# gh-pages con bin/publish-artifact contra un remote rclone local (el     #
# patrón de release-personal.yml), poda de los últimos N por pkgname con  #
# bin/unpublish-packages como mecanismo del db, e issue automático ante   #
# fallo.                                                                  #
# ---------------------------------------------------------------------- #
publish_checks() { # publish_checks <workflow-path>
  local wf="$1"
  grep -qF "repository: robert-flo/omarchy-pkgs" "$wf" || return 1
  grep -qF "ref: personal" "$wf" || return 1
  grep -qF "repository: robert-flo/omarchy-personal-repo" "$wf" || return 1
  grep -qF "ref: gh-pages" "$wf" || return 1
  grep -qF 'ssh-key: ${{ secrets.SSH_DEPLOY_KEY }}' "$wf" || return 1
  grep -qF 'bin/publish-artifact --remote' "$wf" || return 1
  grep -qF -- '--mirror stable --arch x86_64' "$wf" || return 1
  grep -qF 'bin/unpublish-packages' "$wf" || return 1
  grep -qF 'PRUNE_KEEP_N:-5' "$wf" || return 1
  grep -qF "github.event_name == 'repository_dispatch'" "$wf" || return 1
  grep -qF 'secrets.GPG_PRIVATE_KEY' "$wf" || return 1
  grep -qF 'secrets.GPG_PASSPHRASE' "$wf" || return 1
  grep -qF 'ready-for-agent' "$wf" || return 1
  grep -qF 'omarchy-personal.db' "$wf" || return 1
  grep -qF 'omarchy.db.sig' "$wf" || return 1
  grep -qF 'issues: write' "$wf" || return 1
  grep -qF 'actions: read' "$wf" || return 1
  grep -qF 'concurrency:' "$wf" || return 1
  local a b c d e f
  a="$(grep -n '      - name: Upload the package artifact' "$wf" | cut -d: -f1)"
  b="$(grep -n '      - name: Install the publish tooling' "$wf" | cut -d: -f1)"
  c="$(grep -n '      - name: Publish the package into the stable channel' "$wf" | cut -d: -f1)"
  d="$(grep -n '      - name: Prune the channel to the last N packages' "$wf" | cut -d: -f1)"
  e="$(grep -n '      - name: Sign the databases and push gh-pages' "$wf" | cut -d: -f1)"
  f="$(grep -n '      - name: Open the failure issue' "$wf" | cut -d: -f1)"
  [[ -n "$a" && -n "$b" && -n "$c" && -n "$d" && -n "$e" && -n "$f" ]] || return 1
  (( a < b && b < c && c < d && d < e && e < f )) || return 1
  return 0
}
publish_checks "$WORKFLOW" || die 'package.yml does not match the publish-to-personal-repo contract'

# El dogfooding por workflow_dispatch no publica: el gate vive en cada paso
# de publicación.
grep -qxF "        if: github.event_name == 'repository_dispatch'" "$WORKFLOW" || \
  die "publish steps are missing the repository_dispatch gate"

# Mutación: un publish que no usa el mecanismo elegido (publish-artifact)   #
# debe morir en el check.                                                  #
sed 's|bash omarchy-pkgs/bin/publish-artifact --remote|bash omarchy-pkgs/bin/otro-mecanismo --remote|' \
  "$WORKFLOW" > "$TEST_ROOT/package.mutated-publish.yml"
expect_fail 'publish sin publish-artifact' publish_checks "$TEST_ROOT/package.mutated-publish.yml"

# Los pasos de publicación y el issue de fallo son bash válido.
for step in 'Publish the package into the stable channel' \
            'Prune the channel to the last N packages' \
            'Sign the databases and push gh-pages' \
            'Collect the failure log' \
            'Open the failure issue'; do
  script="$TEST_ROOT/step.sh"
  extract_run "$step" > "$script"
  [[ -s "$script" ]] || die "could not extract the step from package.yml: $step"
  bash -n "$script" || die "the extracted step is not valid bash: $step"
done

# Poda funcional: contra un canal de juguete con db de verdad (tar con      #
# desc), la ventana N conserva los últimos y el db manda: un archivo que el #
# db todavía sirve no se toca; si la poda lo tocaría, la reparación corre   #
# bin/unpublish-packages y re-agrega la más nueva con bin/publish-artifact. #
prune_script="$TEST_ROOT/prune.sh"
extract_run 'Prune the channel to the last N packages' > "$prune_script"
[[ -s "$prune_script" ]] || die 'could not extract the prune step from package.yml'

# Stubs del toolkit de omarchy-pkgs (offline): registran la llamada y el    #
# publish-artifact del stub emula el repo-add reescribiendo el db.          #
ws="$TEST_ROOT/ws"
mkdir -p "$ws/omarchy-pkgs/bin"
stub_log="$TEST_ROOT/stub.log"
: > "$stub_log"
cat > "$ws/omarchy-pkgs/bin/unpublish-packages" <<'STUB'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB_LOG"
STUB
cat > "$ws/omarchy-pkgs/bin/publish-artifact" <<'STUB'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB_LOG"
remote=""
pkgfile=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --remote) remote="$2"; shift 2 ;;
    --mirror|--arch) shift 2 ;;
    *) pkgfile="$1"; shift ;;
  esac
done
[[ -n "$remote" && -n "$pkgfile" && -f "$pkgfile" ]] || exit 1
db="$remote/stable/x86_64/omarchy.db.tar.zst"
dir="$(mktemp -d)"
for other in "$pkgfile" $STUB_OTHER; do
  entry="$(basename "$other")"
  entry="${entry%.pkg.tar.zst}"
  mkdir -p "$dir/$entry"
  printf '%%FILENAME%%\n%s\n' "$(basename "$other")" > "$dir/$entry/desc"
done
( cd "$dir" && find . -name desc | sed 's|^\./||' | tar -cf "$db" -T - )
rm -rf "$dir"
STUB

make_db() { # make_db <db_path> <filename servido>...
  local db="$1"; shift
  local dir="$TEST_ROOT/db-build"
  rm -rf "$dir"; mkdir -p "$dir"
  local f entry
  for f in "$@"; do
    entry="${f%.pkg.tar.zst}"
    mkdir -p "$dir/$entry"
    printf '%%FILENAME%%\n%s\n' "$f" > "$dir/$entry/desc"
  done
  ( cd "$dir" && find . -name desc | sed 's|^\./||' | tar -cf "$db" -T - )
}

make_channel() { # make_channel <channel_dir> <filename servido por el db>...
  local channel="$1"; shift
  rm -rf "$channel"; mkdir -p "$channel"
  local i f
  for i in 1 2 3 4 5 6 7; do
    f="git-setup-0.3.0.r${i}.aaaaaaa-3-x86_64.pkg.tar.zst"
    : > "$channel/$f"
    : > "$channel/$f.sig"
  done
  : > "$channel/omarchy-4.0.6-109-x86_64.pkg.tar.zst"
  : > "$channel/omarchy-4.0.6-109-x86_64.pkg.tar.zst.sig"
  make_db "$channel/omarchy.db.tar.zst" "$@"
}

run_prune() { # run_prune <script> <repo_dir> <keep_n> <pkgname>
  local script="$1" repo_dir="$2" keep="$3" pkgname="$4"
  (
    set -Eeuo pipefail
    cd "$ws"
    STUB_LOG="$stub_log" STUB_OTHER='omarchy-4.0.6-109-x86_64.pkg.tar.zst' \
      REPO_DIR="$repo_dir" PKG_NAMES="$pkgname" PKG_BASES="$pkgname" PRUNE_KEEP_N="$keep" \
      bash "$script"
  )
}

db_served_exists() { # db_served_exists <channel>: todo archivo que el db sirve está en el árbol
  local channel="$1" f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -f "$channel/$f" ]] || return 1
  done < <(tar -xO -f "$channel/omarchy.db.tar.zst" --wildcards '*/desc' \
             | awk '/^%FILENAME%$/{getline; print}')
  return 0
}

count_versions() { # count_versions <channel> <pkgname>
  local f count=0
  local re="^$2-.*\.r[0-9]+\.[0-9a-f]+-[0-9]+-[a-z0-9_]+\.pkg\.tar\.zst$"
  for f in "$1"/*.pkg.tar.zst; do
    [[ -e "$f" ]] || continue
    if [[ "$(basename "$f")" =~ $re ]]; then count=$(( count + 1 )); fi
  done
  printf '%s\n' "$count"
}

# Caso A (normal): el db sirve la más nueva; la poda borra las 2 más viejas
# y no llama al toolkit del db (repo-add ya deja una entrada por pkgname).
repo_a="$TEST_ROOT/repo-a"
make_channel "$repo_a/stable/x86_64" \
  'git-setup-0.3.0.r7.aaaaaaa-3-x86_64.pkg.tar.zst' \
  'omarchy-4.0.6-109-x86_64.pkg.tar.zst'
: > "$stub_log"
run_prune "$prune_script" "$repo_a" 5 git-setup
channel_a="$repo_a/stable/x86_64"
[[ "$(count_versions "$channel_a" git-setup)" == 5 ]] || \
  die "poda normal: esperaba 5 git-setup, quedaron $(count_versions "$channel_a" git-setup)"
[[ -e "$channel_a/git-setup-0.3.0.r3.aaaaaaa-3-x86_64.pkg.tar.zst" ]] || die 'poda normal: r3 se fue de más'
[[ -e "$channel_a/git-setup-0.3.0.r3.aaaaaaa-3-x86_64.pkg.tar.zst.sig" ]] || die 'poda normal: la firma de r3 se fue'
[[ ! -e "$channel_a/git-setup-0.3.0.r1.aaaaaaa-3-x86_64.pkg.tar.zst" ]] || die 'poda normal: r1 sobrevivió'
[[ ! -e "$channel_a/git-setup-0.3.0.r2.aaaaaaa-3-x86_64.pkg.tar.zst.sig" ]] || die 'poda normal: la firma de r2 sobrevivió'
[[ -e "$channel_a/omarchy-4.0.6-109-x86_64.pkg.tar.zst" ]] || die 'poda: tocó un paquete ajeno'
db_served_exists "$channel_a" || die 'poda normal: el db quedó sirviendo un archivo que ya no está'
[[ ! -s "$stub_log" ]] || die "poda normal no debió llamar al toolkit del db: $(cat "$stub_log")"

# Caso B (reparación): el db sirve una versión vieja (estado anómalo); la
# poda la protegería para siempre, así que retira la entrada con
# bin/unpublish-packages y re-agrega la más nueva con bin/publish-artifact.
repo_b="$TEST_ROOT/repo-b"
make_channel "$repo_b/stable/x86_64" \
  'git-setup-0.3.0.r2.aaaaaaa-3-x86_64.pkg.tar.zst' \
  'omarchy-4.0.6-109-x86_64.pkg.tar.zst'
: > "$stub_log"
run_prune "$prune_script" "$repo_b" 5 git-setup
channel_b="$repo_b/stable/x86_64"
[[ "$(count_versions "$channel_b" git-setup)" == 5 ]] || \
  die "reparación: esperaba 5 git-setup, quedaron $(count_versions "$channel_b" git-setup)"
[[ ! -e "$channel_b/git-setup-0.3.0.r2.aaaaaaa-3-x86_64.pkg.tar.zst" ]] || die 'reparación: r2 quedó en el árbol'
grep -q 'unpublish-packages' "$stub_log" || die 'la reparación no corrió bin/unpublish-packages'
grep -q 'publish-artifact' "$stub_log" || die 'la reparación no re-agregó la versión nueva'
db_served_exists "$channel_b" || die 'reparación: el db quedó sirviendo un archivo que ya no está'

# Mutación (poda que borra de más): sin reparación y sin guardia, la poda
# borra el archivo que el db todavía sirve y el check del db lo detecta.
prune_bad="$TEST_ROOT/prune-bad.sh"
sed -e 's/^  if \[\[ -n "\$danger" \]\]; then$/  if false; then/' \
    -e 's/^    if grep -qxF "\$f" <<<"\$db_files"; then$/    if false; then/' \
    "$prune_script" > "$prune_bad"
grep -qF 'if false; then' "$prune_bad" || die 'la mutación de la poda no se aplicó al fixture'
repo_c="$TEST_ROOT/repo-c"
make_channel "$repo_c/stable/x86_64" \
  'git-setup-0.3.0.r2.aaaaaaa-3-x86_64.pkg.tar.zst' \
  'omarchy-4.0.6-109-x86_64.pkg.tar.zst'
: > "$stub_log"
run_prune "$prune_bad" "$repo_c" 5 git-setup || die 'la mutación de la poda no llegó a ejecutarse'
expect_fail 'una poda que borra de más deja el db sirviendo un archivo borrado' \
  db_served_exists "$repo_c/stable/x86_64"

# Mutación (default de la ventana): si el N default deja de ser 5, la poda
# conserva menos de lo prometido y el check del conteo lo detecta.
prune_n3="$TEST_ROOT/prune-n3.sh"
sed 's/PRUNE_KEEP_N:-5/PRUNE_KEEP_N:-3/' "$prune_script" > "$prune_n3"
grep -qF 'PRUNE_KEEP_N:-3' "$prune_n3" || die 'la mutación del N default no se aplicó al fixture'
repo_d="$TEST_ROOT/repo-d"
make_channel "$repo_d/stable/x86_64" \
  'git-setup-0.3.0.r7.aaaaaaa-3-x86_64.pkg.tar.zst' \
  'omarchy-4.0.6-109-x86_64.pkg.tar.zst'
: > "$stub_log"
run_prune "$prune_n3" "$repo_d" 3 git-setup
[[ "$(count_versions "$repo_d/stable/x86_64" git-setup)" == 3 ]] || \
  die 'la mutación del N default no cambió la ventana'

printf '%s\n' 'ok package-workflow'
