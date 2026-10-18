# git-setup for Arch Linux

An Arch Linux installation package for
[git-setup](https://github.com/robert-flo/pj-domina-rf-git-setup), built
with the same local PKGBUILD workflow used by AUR packages. Clone the package
repository, inspect or adjust PKGBUILD if needed, then build a Pacman package
on your machine. It is not published to AUR yet.

Upstream project: [robert-flo/pj-domina-rf-git-setup.git](https://github.com/robert-flo/pj-domina-rf-git-setup.git)

The installed package provides the public git-setup command at
/usr/bin/git-setup, keeps the private implementation under /opt/git-setup,
and adds an application-menu entry that opens the assistant in the default
terminal.

---

<br>

<a id="installation"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=INSTALLATION" width="450"/>

### Build and Install Locally

Clone this package repository, then choose either installation workflow.

### Standard Arch / AUR-Style Workflow

```shell
git clone https://github.com/robert-flo/pj-domina-rf-git-setup-arch.git
cd pj-domina-rf-git-setup-arch
makepkg -si
```

This is the conventional workflow for a local PKGBUILD or an AUR package:
makepkg builds the Pacman package and -i installs it.

### Project Make Workflow

```shell
git clone https://github.com/robert-flo/pj-domina-rf-git-setup-arch.git
cd pj-domina-rf-git-setup-arch
make install
```

make install runs makepkg -si for you and adds the project's formatted status
messages and next-action guidance. Use one workflow or the other; do not run
make install followed by makepkg -si, because both perform the same package
build-and-install operation.

After installation, run git-setup to open the interactive menu.

The package downloads the tagged release archive pinned by PKGBUILD,
verifies its fixed SHA-256 checksum, and installs only the launcher plus the
release payload. It requires git, github-cli, gnupg, openssh, and git-delta.

### Application Menu

The package installs git-setup.desktop at
/usr/share/applications/git-setup.desktop. In a graphical desktop environment
it appears as **git-setup**, uses the theme-provided generic terminal icon
(utilities-terminal), and opens git-setup in the system's default terminal
emulator.

The launcher uses Terminal=true; it does not start a separate graphical UI.

---

<br>

<a id="package-workflow"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=PACKAGE%20WORKFLOW" width="450"/>

The repository wraps the usual package-maintenance tasks in make targets:

```shell
make build       # makepkg -s: build without installing
make install     # makepkg -si: build or reuse, then install
make reinstall   # makepkg -Cfi: force a clean rebuild and installation
make clean       # remove src/, pkg/, downloaded archives, and package artifacts
make lint        # check Bash, ShellCheck, .SRCINFO, and whitespace
```

Run make reinstall after changing PKGBUILD or when a package artifact from an
earlier build is present. Run make clean when you want a completely clean
checkout for a fresh package build.

Use make help for the complete, interactive list. The Makefile follows the
same command-center conventions as the source repository: each target explains
its work, reports success, and suggests the relevant next actions.

---

<br>

<a id="validation"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=VALIDATION" width="450"/>

The package has two deliberately separate Docker validations. Both use
docker run --rm; neither installs or upgrades host packages, mounts the host
home directory, Git configuration, SSH keys, GPG keys, or package cache.

```shell
make test-release
make test-local SOURCE_DIR=/path/to/git-setup
make test SOURCE_DIR=/path/to/git-setup
```

SOURCE_DIR is equivalent to GIT_SETUP_SOURCE_DIR. It must identify a Git
worktree containing the source repository's root git-setup dispatcher.

### Published Release Archive

make test-release checks release integrity only. Inside a disposable
archlinux:latest container it rejects SKIP or malformed archive checksums,
downloads every PKGBUILD source entry, and runs makepkg --verifysource.

It does not build, install, or execute git-setup. The stock Arch image already
provides makepkg, curl, and SHA-256 tooling, so this validation installs no
container packages and does not need base-devel.

Run it after publishing a tag or changing release metadata. It fails when
GitHub is unavailable, a source is missing, or a checksum differs.

### Local Package Installation

make test-local SOURCE_DIR=... validates an actual committed source revision.
It creates a temporary archive from git archive HEAD, redirects PKGBUILD to
that local archive, builds and installs the package in a disposable Arch
container, and exercises the installed public command.

The source snapshot contains committed HEAD only. Staged, unstaged, ignored,
and untracked source files are not included; commit source changes before
running this validation.

The local archive is intentionally different from GitHub's generated release
archive, so this validation uses --skipchecksums. The release validation above
independently verifies the published archive with its fixed checksum.

Inside the disposable container, the local validation installs:

```shell
fakeroot sudo git github-cli gnupg openssh git-delta
```

fakeroot lets the unprivileged builder create the package, while sudo allows
makepkg -i to invoke Pacman. The remaining commands are the runtime
dependencies declared by PKGBUILD and exercised by git-setup.

The Pacman transaction can list many more packages because Arch refreshes the
base image and installs transitive dependencies. Those packages, downloads,
and installed sizes belong exclusively to the disposable container.

This package is Bash and static templates only, declares arch=('any'), has no
compilation step, and disables debug-package generation. base-devel is
therefore unnecessary for the current validator. If native compilation is
introduced later, restore a full base-devel environment and update this
documentation.

Each validator also has direct terminal help:

```shell
tests/validate-release-archive.sh --help
tests/validate-local-install.sh --help
```

---

<br>

<a id="repository-roles"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=REPOSITORY%20ROLES" width="450"/>

The source repository contains the interactive assistant and publishes version
tags. This repository contains the Arch PKGBUILD, public launcher, desktop-entry
integration, and package validations.

Keeping the repositories separate lets the release archive remain the package
input while package-specific build, installation, and validation logic stays
here.

### Automated Upstream Updates

GitHub Actions checks the latest stable release from the source repository once
per day at 06:23 UTC (00:23 in El Salvador) and can also be run manually. When
either the release version or its generated source-archive checksum changes, the
workflow updates PKGBUILD,
regenerates .SRCINFO, builds the package as a non-root user, uploads the package
artifact, and commits the verified metadata back to this repository.

The workflow uses scripts/check_upstream.sh for release detection and checksum
calculation, and scripts/update_package.sh for the controlled PKGBUILD edit. The
offline contract test is available locally with:

```shell
make test-automation
```

To run the real release check locally, update the metadata when necessary, and
then review the result before committing it:

```shell
make update-upstream
git diff -- PKGBUILD .SRCINFO
make build
make test-release
```

`make update-upstream` requires an authenticated GitHub CLI session (`gh auth
login`) plus `curl`, `jq`, and Arch's `makepkg`. It never commits or pushes.

This repository is still not published to AUR, so the automation stops after
updating and validating this package repository. AUR publication will require
an AUR package repository and a dedicated SSH key.

---

<br>

## License

The packaged source is released under the
[source project's MIT License](https://github.com/robert-flo/pj-domina-rf-git-setup/blob/master/LICENSE).
