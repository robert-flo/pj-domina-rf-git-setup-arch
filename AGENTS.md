# AGENTS.md

Repo de empaquetado Arch del dúo `pj-domina-rf-git-setup` / `pj-domina-rf-git-setup-arch`.
La fuente del paquete (contrato del launcher y del código instalado) vive en
`pj-domina-rf-git-setup`; acá viven el PKGBUILD, el workflow `package.yml` y la
publicación al repo personal. Los cambios de empaquetado nacen en este repo y
los demás `-arch` del proyecto heredan (spec despliegue-duo-arch-por-commit v2,
ticket 4/5).

## Pruebas por capacidad

Las pruebas se definen por lo que el entorno del agente permite, nunca por su
identidad. El piso es el mismo para todos; lo que cambia es lo que cada entorno
puede agregar encima.

- El WK NUNCA instala: `pacman -U` está prohibido en la PC de Roberto; pacman
  queda limpio para su prueba final (`pacman -Syu` sobre el paquete publicado).
- Piso para todos: el CI del -arch verifica la instalación en contenedor Arch;
  Evidence declara qué corrió y qué quedó al CI.

### Sondeo del entorno

Antes de probar, el agente sondea lo que tiene a mano (pacman, makepkg,
permisos) y elige el camino más completo que su entorno permita, sin descartar
pruebas ni obligarlas al 100%:

1. ¿Hay `makepkg` y permisos para construir sin tocar pacman? → construye con
   `make build` (makepkg -s, nunca -i ni -si) y corre los tests del repo.
2. ¿No hay `makepkg` o el entorno no puede construir? → corre los tests offline
   del repo (`bash tests/test-package-workflow.sh`,
   `bash tests/test-upstream-automation.sh`) y deja la construcción y la
   instalación al CI.

En ningún caso `pacman -U`, `pacman -S`, `make install` ni `make reinstall`
corren fuera del contenedor de CI.

### Declaración en Evidence

Todo PR declara al final de Evidence, con este formato:

- Corrido: los comandos que corrieron en el entorno del agente, con resultado.
- Al CI: la verificación que queda para el run post-merge (construcción,
  `pacman -U` en contenedor, instalación).
- Motivo del entorno: una línea cuando algo no corrió acá (sin makepkg, sin
  root, dash sin sustitución de proceso, etc.).

Si el entorno permitió todo, la línea de motivo se omite; el piso del CI
siempre queda declarado.
