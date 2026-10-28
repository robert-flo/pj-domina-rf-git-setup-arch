#!/usr/bin/env bash

# Runs INSIDE the disposable archlinux:latest container started by
# validate-local-install.sh. Never run this on the host.
#
# Expects, mounted read-only by the caller:
#   /package               the git-setup package sources (PKGBUILD, etc.)
#   /archive/git-setup-${PKG_VERSION}.tar.gz   the local source snapshot
#
# Expects, from the environment:
#   PKG_VERSION             package version, matches the archive filename

set -Eeuo pipefail

readonly TEST_HOME=/tmp/git-setup-package-test
readonly TEST_NAME="Package Test"
readonly TEST_EMAIL="package-test@example.com"

phase_install_prereqs() {
  printf '\n==> [container 1/5] Refreshing Arch and installing exact prerequisites\n'
  printf '    These packages exist only inside this disposable container.\n\n'
  pacman -Syu --noconfirm --needed fakeroot sudo git github-cli gnupg openssh git-delta
}

phase_create_builder_user() {
  printf '\n==> [container 2/5] Creating the unprivileged makepkg user\n'
  useradd --create-home builder
  printf 'builder ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/builder
  chmod 0440 /etc/sudoers.d/builder
}

phase_prepare_workspace() {
  printf '==> [container 3/5] Preparing the writable package workspace\n'
  install -d -m 0755 /work/package
  cp -a /package/. /work/package/

  # The checkout may contain ignored makepkg artifacts.  They must not let this
  # validation install an older package instead of building the current
  # PKGBUILD and desktop entry.
  find /work/package -maxdepth 1 -type f -name '*.pkg.tar.*' -delete

  # A local git archive has different bytes from the published GitHub archive.
  # Redirect PKGBUILD to it here.
  sed -i \
    "s|\${url}/archive/refs/tags/v\${pkgver}.tar.gz|file:///archive/git-setup-${PKG_VERSION}.tar.gz|" \
    /work/package/PKGBUILD

  chown -R builder:builder /work/package
}

phase_build_and_install() {
  printf '==> [container 4/5] Building and installing the local package\n'
  su --shell /bin/bash builder --command \
      'cd /work/package && makepkg -Cfi --noconfirm --needed --skipchecksums'
}

phase_verify_desktop_launcher() {
  local desktop_file=/usr/share/applications/git-setup.desktop

  test -f "$desktop_file"
  grep -Fxq '[Desktop Entry]' "$desktop_file"
  grep -Fxq 'Name=git-setup' "$desktop_file"
  grep -Fxq 'Exec=git-setup' "$desktop_file"
  grep -Fxq 'TryExec=git-setup' "$desktop_file"
  grep -Fxq 'Terminal=true' "$desktop_file"
  grep -Fxq 'Type=Application' "$desktop_file"
  grep -Fxq 'Icon=utilities-terminal' "$desktop_file"
  grep -Fxq 'Categories=Development;Utility;' "$desktop_file"
}

phase_verify_config_command() {
  test -x /usr/bin/git-setup
  test -x /opt/git-setup/git-setup

  HOME="$TEST_HOME" NAME="$TEST_NAME" EMAIL="$TEST_EMAIL" TERM=dumb \
    /usr/bin/git-setup config > /tmp/git-setup-package-output

  test "$(git config --file "$TEST_HOME/.config/git/config" --get user.name)" = "$TEST_NAME"
  test "$(git config --file "$TEST_HOME/.config/git/config" --get core.pager)" = delta
  grep -Fq "Git Configuration Files" /tmp/git-setup-package-output
}

phase_verify_verify_command() {
  HOME="$TEST_HOME" TERM=dumb /usr/bin/git-setup verify \
    > /tmp/git-setup-package-verify-output || true
  grep -Fq "Generated Git Configuration Files" /tmp/git-setup-package-verify-output
}

phase_verify_clean_command() {
  printf 'no\n' | HOME="$TEST_HOME" TERM=dumb /usr/bin/git-setup clean \
    > /tmp/git-setup-package-clean-output
  grep -Fq "Cancelled" /tmp/git-setup-package-clean-output
  test -f "$TEST_HOME/.config/git/config"
}

phase_verify_menu_command() {
  printf 'q\n' | HOME="$TEST_HOME" TERM=dumb /usr/bin/git-setup \
    > /tmp/git-setup-package-menu-output
  grep -Fq "Choose an action" /tmp/git-setup-package-menu-output
}

phase_exercise_public_commands() {
  printf '\n==> [container 5/5] Confirming the installed public commands behave as expected\n'
  phase_verify_desktop_launcher
  phase_verify_config_command
  phase_verify_verify_command
  phase_verify_clean_command
  phase_verify_menu_command
  printf '==> [container 5/5] PASS: desktop launcher, config, verify, cancelled clean, and the menu behaved as expected\n'
}

main() {
  phase_install_prereqs
  phase_create_builder_user
  phase_prepare_workspace
  phase_build_and_install
  phase_exercise_public_commands
}

main "$@"
