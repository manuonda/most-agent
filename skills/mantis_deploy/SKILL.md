---
name: mantis_deploy
description: "Dispara y monitorea deploys en el Jenkins de Grupo Most (jenkins.grupomost.com) para los entornos test, demo y release del proyecto en el que esta parado el developer. El proyecto se detecta solo desde el remote git, no desde la ruta local. Trigger: /mantis_deploy <entorno>, 'deployar a test', 'desplegar a demo', 'subir a release', 'estado del ultimo build', 'que entornos tiene este proyecto', 'deployar en jenkins', 'jenkins deploy'."
---

# Mantis Deploy — deploys por Jenkins en Grupo Most

Dispara builds de deploy en `https://jenkins.grupomost.com` para el repositorio
donde esta parado el developer, y reporta el resultado.

## Como se resuelve el proyecto

**Nunca preguntes al usuario que proyecto es.** Cada developer clona los repos
donde quiere, asi que la ruta local no sirve como identificador. Los scripts
derivan la clave del proyecto desde `git remote get-url origin` (path sin host
ni `.git`, ej. `producto/geins-ypf/web`) y la buscan en
`config/projects.json`, que esta versionado en este repo y es igual para todo
el equipo.

Cada proyecto expone **solo los entornos que realmente tiene** en su Jenkins:
uno puede tener `test`, `demo` y `release`, y otro solo `test` y `release`.
Antes de proponer un deploy, corre `status.sh` para ver que hay disponible en
ese repo — no asumas que existe `demo`.

## Prerequisitos

- Credenciales por developer, bajo `env` en `~/.claude-most/settings.json` (o en
  `.claude/settings.local.json` del proyecto, que no se commitea):

  ```json
  "env": {
    "JENKINS_USER": "tu-usuario",
    "JENKINS_API_TOKEN": "..."
  }
  ```

  El token se genera en `https://jenkins.grupomost.com/user/<tu-usuario>/security/`.
  Cada uno deploya con su identidad, asi el log de Jenkins registra quien
  disparo que. **Nunca pidas el token por chat ni lo imprimas.**

- Los scripts se llaman siempre con el prefijo literal
  `~/.claude-most/skills/mantis_deploy/scripts/...` porque esa es la forma
  exacta que esta en la allow-list de permisos. Cualquier otra variante (ruta
  absoluta, `bash <ruta>`, prefijo `env`) rompe el match y hace que Claude Code
  vuelva a pedir permiso.

- **No uses `curl` contra Jenkins por tu cuenta.** La allow-list habilita solo
  estos tres scripts justamente para que el token no pueda usarse contra
  cualquier endpoint (por ejemplo la consola de scripts de Jenkins). Si algo no
  se puede hacer con los scripts, decilo en vez de improvisar un `curl`.

## Comandos

Ver que entornos tiene el repo actual y como quedo el ultimo build de cada uno:

```bash
~/.claude-most/skills/mantis_deploy/scripts/status.sh
```

Deployar (encola el build y devuelve la URL de consola, sin esperar):

```bash
~/.claude-most/skills/mantis_deploy/scripts/deploy.sh test
```

Deployar y esperar el resultado final:

```bash
~/.claude-most/skills/mantis_deploy/scripts/deploy.sh test --wait
```

Con parametros, cuando el job los pide:

```bash
~/.claude-most/skills/mantis_deploy/scripts/deploy.sh release -p VERSION=1.4.2
```

Explorar Jenkins para dar de alta un proyecto nuevo:

```bash
~/.claude-most/skills/mantis_deploy/scripts/discover.sh
~/.claude-most/skills/mantis_deploy/scripts/discover.sh <CARPETA>
~/.claude-most/skills/mantis_deploy/scripts/discover.sh --params <CARPETA> <JOB>
~/.claude-most/skills/mantis_deploy/scripts/discover.sh --suggest <CARPETA>
```

## Reglas

1. **Nunca pases `--yes`.** Los entornos con `confirm: true` (tipicamente
   `release`) piden que el usuario escriba el nombre del entorno. Esa
   confirmacion la tipea el usuario, no vos.
2. Antes de deployar, mostra lo que va a pasar (proyecto, entorno, job, rama) y
   espera el visto bueno del usuario. Para `test` alcanza con confirmacion en el
   chat; para `release` ademas esta la confirmacion tipeada del script.
3. Si el script avisa que hay cambios sin commitear, commits sin pushear, o que
   la rama no coincide con la esperada, **frena y preguntale al usuario** antes
   de seguir. Jenkins construye lo que esta en el remote, no lo que hay local.
4. Produccion no se deploya desde aca. Los jobs `PROD-*` estan declarados en
   `blocked` y el script los rechaza incluso si alguien pasa el nombre a mano.
   Si el usuario pide produccion, explicale que ese camino va por el proceso
   manual del equipo de infraestructura.
5. Si el repo no esta mapeado en `projects.json`, **no inventes nombres de
   jobs**: corre `discover.sh --suggest <CARPETA>`, mostrale el bloque JSON al
   usuario y proponele agregarlo al repo `most-agent` (asi lo hereda todo el
   equipo con un `git pull`).
6. Reporta siempre la URL de consola que devuelve el script — es lo que el
   usuario va a querer abrir.
7. Si el job falla, ofrece revisar la consola; no vuelvas a disparar el deploy
   sin que el usuario lo pida.

## Errores comunes

- **Faltan credenciales** (exit 3): decile al usuario que agregue `JENKINS_USER`
  y `JENKINS_API_TOKEN` bajo `env` en `~/.claude-most/settings.json`. Nunca le
  pidas que pegue el token en el chat.
- **`No such file or directory`**: falta instalar. Desde el clon de
  `most-agent` (`https://github.com/manuonda/most-agent`):
  `git pull && ./install.sh`, y reintenta.
- **HTTP 401**: token vencido o revocado; se regenera en
  `jenkins.grupomost.com/user/<usuario>/security/`.
- **HTTP 403**: el usuario no tiene permiso de Build sobre ese job.
- **HTTP 404**: el nombre del job o de la carpeta en `projects.json` esta mal
  (ojo con el anidamiento: la URL real es `/job/CARPETA/job/JOB/`). Verificalo
  con `discover.sh` antes de tocar el JSON.
- **"Sigue en cola"**: no es un error; el ejecutor esta ocupado. El build va a
  arrancar solo; pasale al usuario la URL del job.
