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

**`--wait` es el modo por default cuando el usuario pide deployar desde el
chat.** El script sondea Jenkins hasta que el build termina, imprime
`Resultado: SUCCESS|FAILURE|ABORTED|...` y sale con codigo 0 solo si fue
`SUCCESS`. Comunicale ese resultado al usuario tal cual (no alcanza con pasar
la URL de cola) y segui distinto segun el caso:

- **SUCCESS**: confirmalo. Si el usuario quiere ver el resultado, el skill
  `mantis_preview` abre el entorno de test en Chrome.
- **FAILURE / ABORTED / UNSTABLE**: decilo explicitamente y ofrece revisar la
  consola (la URL que imprime el script). No reintentes el deploy por tu
  cuenta.

Usa `deploy.sh <entorno>` sin `--wait` solo si el usuario pide explicitamente
no esperar ("dispara y segui"). En ese caso, para saber como termino despues
no dispares un deploy nuevo: consulta `status.sh <entorno>`.

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

## Registrar el resultado en el company brain

Despues de que `deploy.sh <entorno> --wait` termina (SUCCESS o no), si la rama actual
sigue la convencion de `mantis_develop` (`feature/mantis_0<ISSUE_NUMBER>`, zero-padded a
7 digitos), dejá el resultado en la nota del issue para que quede una cronologia de
deploys sin que nadie tenga que reconstruirla despues:

1. Extrae el numero de issue de la rama (`feature/mantis_00198835` -> `198835`, sacando
   los ceros a la izquierda). Si la rama NO matchea ese patron (por ejemplo estas parado
   en `test` o en una rama de release compartida), **no escribas nada en el brain** — no
   hay un issue puntual al cual asociar el deploy.
2. Ubica la nota: `~/.claude-most/brain/mantis/*/<ISSUE_NUMBER>.md` (glob, como hace
   `company_brain`). Si no existe todavia, seguí el operacion "Save/update a note" de
   `skills/company_brain/SKILL.md` para crearla (necesitas el nombre del proyecto vía
   `~/.claude-most/bin/mantis-api.sh issue <ISSUE_NUMBER>` para el slug de la carpeta).
3. Agrega (no reemplaces) una linea bajo una seccion `## Deploys` en esa nota, creandola
   si no existe, con este formato:

   ```
   - **<entorno>** — build #<N> (<RESULTADO>), rama `<rama>`, <YYYY-MM-DD HH:MM>
     Consola: <url>   <!-- solo si RESULTADO no es SUCCESS -->
   ```

4. Publica automaticamente (sin pedir confirmacion — el resultado es un hecho, no texto a
   revisar, misma logica que `mantis_comment`):

   ```bash
   ~/.claude-most/bin/brain-publish.sh <ISSUE_NUMBER>
   ```

   - Exit 0: mencioná en el resumen que el resultado quedo publicado en el brain (a menos
     que la salida diga que no habia nada que publicar).
   - Exit 2/3 (conflicto de pull o push rechazado): reportá la salida exacta del script;
     la nota queda commiteada local, el developer puede reintentar con
     `/company_brain publicar <ISSUE_NUMBER>`. Esto no afecta el resultado del deploy en si.

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
8. Para mostrar visualmente el resultado en test (abrir el sitio en Chrome),
   usa el skill `mantis_preview` — no repliques esa logica aca.
9. Nunca corras `git`/commit/push contra `~/.claude-most/brain` a mano: el
   unico camino permitido es `~/.claude-most/bin/brain-publish.sh` (ver
   "Registrar el resultado en el company brain" mas arriba).

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
