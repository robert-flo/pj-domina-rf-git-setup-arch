#!/usr/bin/env bash

# Contrato del wrapper vendido y del ship del cron (ticket #8, guardas 4b y 4c).
#
# 4b: el target del exec del wrapper coincide con la ruta que package()
#     instala en el payload; si alguien cambia una de las dos sin la otra,
#     la suite falla antes del run.
# 4c: el archivo vendido sigue siendo el wrapper (su primera instruccion
#     ejecutable es exec de /opt/<pkgname>/...); un espejo accidental del
#     launcher de la fuente muere aqui, no en produccion.
# Ademas: el cron de update-upstream no empuja directo a la rama default;
# el ship va por PR con automerge en CI verde.

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKGBUILD_PATH="${ROOT_DIR}/PKGBUILD"
WORKFLOW_PATH="${ROOT_DIR}/.github/workflows/update-upstream.yml"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vendored-contract.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail_test() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1" >&2; }

read_pkgbuild_value() { # read_pkgbuild_value <name> <file>
  awk -F= -v name="$1" '$1 == name { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' "$2"
}

# Ruta que el wrapper ejecuta: el segundo campo de la primera linea exec.
first_exec_target() { # first_exec_target <vendored>
  awk '/^[[:space:]]*exec /{ print $2; exit }' "$1"
}

# Ruta que package() instala para el launcher real: el target de la linea
# install cuyo origen vive en ${source_dir} (el wrapper se instala aparte,
# desde ${srcdir}, y no cuenta).
package_install_rel() { # package_install_rel <pkgbuild>
  awk -F '"' '/install .*"\$\{source_dir\}\// { print $4; exit }' "$1"
}

# Directorio del payload declarado en package(), sin el prefijo ${pkgdir}/.
package_payload_dir() { # package_payload_dir <pkgbuild>
  awk -F= '/payload_dir=/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' "$1"
}

# 4b: exit 0 si el exec del wrapper apunta a lo que package() instala.
guard_4b() { # guard_4b <vendored> <pkgbuild> <pkgname>
  local vendored="$1" pkgbuild="$2" pkgname="$3"
  local exec_target rel payload expected
  exec_target="$(first_exec_target "$vendored")"
  rel="$(package_install_rel "$pkgbuild")"
  payload="$(package_payload_dir "$pkgbuild")"
  payload="${payload%\"}"
  payload="${payload#\"}"
  rel="${rel#\$\{payload_dir\}/}"
  payload="${payload#\$\{pkgdir\}/}"
  expected="/${payload}/${rel}"
  expected="${expected//\$\{pkgname\}/${pkgname}}"
  [[ -n $exec_target ]] || { printf '4b: el wrapper no tiene exec\n' >&2; return 1; }
  [[ -n $rel && -n $payload ]] || { printf '4b: package() no declara la instalacion del launcher\n' >&2; return 1; }
  [[ "$exec_target" == "$expected" ]] || {
    printf '4b: el wrapper exec %s pero package() instala %s\n' "$exec_target" "$expected" >&2
    return 1
  }
  return 0
}

# 4c: exit 0 si el archivo vendido sigue siendo el wrapper.
guard_4c() { # guard_4c <vendored> <pkgname>
  local vendored="$1" pkgname="$2" first
  if grep -qE 'RUNTIME_DIR|scrDir|source "' "$vendored"; then
    printf '4c: el archivo vendido parece un espejo del launcher de la fuente\n' >&2
    return 1
  fi
  first="$(awk '/^[[:space:]]*exec /{ print NR; exit }' "$vendored")"
  [[ -n $first ]] || { printf '4c: el wrapper no tiene exec de /opt/%s\n' "$pkgname" >&2; return 1; }
  if (( first > 10 )); then
    printf '4c: el primer exec del wrapper esta en la linea %s\n' "$first" >&2
    return 1
  fi
  if grep -vE '/opt/' < <(awk '/^[[:space:]]*exec /{ print $2 }' "$vendored") | grep -q .; then
    printf '4c: una linea exec del wrapper no apunta a /opt/\n' >&2
    return 1
  fi
  return 0
}

# El cron no empuja directo a la rama default: el ship va por PR.
guard_cron_no_push() { # guard_cron_no_push <workflow>
  if grep -q 'git push' "$1"; then
    printf 'el cron de update-upstream empuja directo con git push\n' >&2
    return 1
  fi
  return 0
}

mutate() { # mutate <src> <dst> <old_literal> <new_literal>
  awk -v old="$3" -v new="$4" '
    { while ((i = index($0, old)) > 0) $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); print }
  ' "$1" > "$2"
}

main() {
  local pkgname vendored
  pkgname="$(read_pkgbuild_value pkgname "$PKGBUILD_PATH")"
  vendored="${ROOT_DIR}/${pkgname}"
  [[ -f $vendored ]] || { printf 'no encuentro el archivo vendido %s\n' "$vendored" >&2; exit 1; }

  if guard_4b "$vendored" "$PKGBUILD_PATH" "$pkgname"; then
    ok "4b: exec del wrapper == ruta instalada por package()"
  else
    fail_test "4b: exec del wrapper no coincide con package()"
  fi

  if guard_4c "$vendored" "$pkgname"; then
    ok "4c: el vendido sigue siendo el wrapper"
  else
    fail_test "4c: el vendido dejo de ser el wrapper"
  fi

  if guard_cron_no_push "$WORKFLOW_PATH"; then
    ok "el cron no empuja directo a la default"
  else
    fail_test "el cron empuja directo a la default"
  fi

  # Mutaciones: cada una debe morir en su guard.
  local m1="${TMP_ROOT}/m1" m2="${TMP_ROOT}/m2" m3="${TMP_ROOT}/m3.yml"
  mutate "$vendored" "$m1" "exec /opt/${pkgname}/" "exec /opt/otra/ruta/"
  if guard_4b "$m1" "$PKGBUILD_PATH" "$pkgname"; then
    fail_test "mutacion exec-target: el guard 4b no la cubre"
  else
    ok "mutacion exec-target: muere en el guard 4b"
  fi

  { # shellcheck disable=SC2016 # literales del launcher que el guard busca
    printf '#!/usr/bin/env bash\n'
    # shellcheck disable=SC2016 # literales del launcher que el guard busca
    printf 'scrDir="$(dirname "$(readlink -f "${0}")")"\n'
    # shellcheck disable=SC2016
    printf 'RUNTIME_DIR="$scrDir/runtime"\n'
    printf 'exec /opt/%s/git-setup "$@"\n' "$pkgname"
  } > "$m2"
  if guard_4c "$m2" "$pkgname"; then
    fail_test "mutacion espejo-del-launcher: el guard 4c no la cubre"
  else
    ok "mutacion espejo-del-launcher: muere en el guard 4c"
  fi

  cp "$WORKFLOW_PATH" "$m3"
  # shellcheck disable=SC2016 # linea literal que el guard busca
  printf '          git push origin "HEAD:$GITHUB_REF_NAME"\n' >> "$m3"
  if guard_cron_no_push "$m3"; then
    fail_test "mutacion push-directo: el guard del cron no la cubre"
  else
    ok "mutacion push-directo: muere en el guard del cron"
  fi

  printf '%d ok, %d fail\n' "$PASS" "$FAIL"
  (( FAIL == 0 ))
}

main "$@"
