pkgname=git-setup
# La versión rastreable la calcula el job de CI (package.yml) y la entrega
# por PKGVER: base.r<N>.<shortsha>, con N de `git describe --long` sobre el
# sha empaquetado (sin tags, total de commits). Sin PKGVER, makepkg local
# usa la base del último release empaquetado.
pkgver="${PKGVER:-0.2.0}"
pkgrel=3
pkgdesc='Configure Git, GitHub, SSH and GPG interactively'
arch=('any')
url='https://github.com/robert-flo/pj-domina-rf-git-setup'
license=('MIT')
options=('!debug')
depends=('git' 'github-cli' 'gnupg' 'openssh' 'git-delta')
source=(
  "${pkgname}-${pkgver}.tar.gz"
  "${pkgname}"
)
sha256sums=(
  'SKIP'
  'e1940018f1f1f042fdb697fdfcf022076cfcd2821c3689aaa3fd5c6d3583f150'
)

package() {
  local source_dir="${srcdir}/pj-domina-rf-git-setup-${pkgver}"
  local payload_dir="${pkgdir}/opt/${pkgname}"

  # El launcher es la fuente de verdad del layout: resuelve
  # RUNTIME_DIR="$scrDir/runtime" sin fallback, así que el runtime viaja
  # anidado bajo el payload con el mismo árbol de la fuente. Así
  # /opt/git-setup/git-setup resuelve su runtime directo, y
  # /usr/bin/git-setup (el wrapper que hace exec del launcher) también.
  # commands.tsv y completion viajan dentro del runtime: command_catalog
  # lee el catálogo con ../commands.tsv y la completion zsh (_git-setup)
  # referencia la misma ruta relativa.
  install -d "${payload_dir}/runtime"/{helper,lib,scripts,templates/git,completion}
  install -Dm755 "${source_dir}/git-setup" "${payload_dir}/git-setup"
  install -Dm755 "${source_dir}/runtime/helper/"* "${payload_dir}/runtime/helper/"
  install -Dm755 "${source_dir}/runtime/lib/"* "${payload_dir}/runtime/lib/"
  install -Dm755 "${source_dir}/runtime/scripts/"* "${payload_dir}/runtime/scripts/"
  install -Dm644 "${source_dir}/runtime/templates/git/"* "${payload_dir}/runtime/templates/git/"
  install -Dm644 "${source_dir}/runtime/commands.tsv" "${payload_dir}/runtime/commands.tsv"
  install -Dm644 "${source_dir}/runtime/completion/"* "${payload_dir}/runtime/completion/"
  install -Dm755 "${srcdir}/${pkgname}" "${pkgdir}/usr/bin/${pkgname}"
  install -Dm644 /dev/stdin "${pkgdir}/usr/share/applications/${pkgname}.desktop" << 'DESKTOP_ENTRY'
[Desktop Entry]
Name=git-setup
Comment=Configure Git, GitHub, SSH and GPG interactively
Exec=git-setup
TryExec=git-setup
Terminal=true
Type=Application
Icon=utilities-terminal
Categories=Development;Utility;
Keywords=Git;GitHub;SSH;GPG;
DESKTOP_ENTRY
}
