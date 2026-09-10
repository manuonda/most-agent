---
name: mantis_deploy
description: "Dispara y monitorea deploys en el Jenkins de Grupo Most (jenkins.grupomost.com) para los entornos test, demo y release del proyecto en el que esta parado el developer. El proyecto se detecta solo desde el remote git, no desde la ruta local. Trigger: /mantis_deploy <entorno>, /mantis_deploy listado, 'deployar a test', 'desplegar a demo', 'subir a release', 'estado del ultimo build', 'que entornos tiene este proyecto', 'deployar en jenkins', 'jenkins deploy', 'que repos estan mapeados', 'listado de jenkins', 'como esta configurado esto'."
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

**Siempre decile al usuario en que repo/proyecto estas parado.** En cualquier
invocacion del skill (con o sin entorno), antes de hacer nada mas:

1. Resolvé el proyecto (`git remote get-url origin` → clave en `projects.json`)
   y decile al usuario que proyecto detectaste.
2. Si la clave **no esta** en `config/projects.json`: decilo explicitamente
   ("este repo no esta mapeado en projects.json"), ofrecele mostrarle el
   `listado` completo (ver abajo) para que vea que otros repos si estan
   configurados, y segui la regla 5 — no inventes un job ni intentes
   deployar.
3. Si esta mapeado, corre `status.sh` y mostrale los entornos disponibles para
   ese proyecto (y el estado del ultimo build de cada uno). Este paso es
   siempre informativo, se haya pedido un entorno puntual o no.

## Ver el mapeo completo (`/mantis_deploy listado`)

Trigger: `/mantis_deploy listado`, "que repos estan mapeados", "listado de
jenkins", "como esta configurado esto", "que proyectos tiene el mantis_deploy".

Esto es **distinto** de `status.sh`: `status.sh` muestra los entornos del
proyecto donde estas parado ahora; `listado` muestra **todos** los proyectos
declarados en la configuracion, esten o no relacionados con el repo actual.

No hace falta pegarle a Jenkins ni correr ningun script para esto — es
informacion estatica versionada en el repo. Simplemente leé con el tool Read
el archivo `~/.claude-most/skills/mantis_deploy/config/projects.json` (ya
esta cubierto por el permiso `Read(//home/manuonda/.claude-most/**)`, no hace
falta Bash) y mostrale al usuario, por cada proyecto declarado bajo
`projects`:

- la clave de remote (ej. `producto/geins-ypf/web`) — es lo que identifica al
  repo, no la ruta local de nadie.
- `display_name` y `folder` de Jenkins.
- cada entorno en `environments`, con su `job` y si tiene `confirm: true`.
- los jobs de `blocked` si el proyecto los declara (produccion, nunca
  deployable desde aca).
- si algun `job`/`folder` todavia dice `TODO-completar-con-discover`,
  marcalo como pendiente y recordá que se completa con `discover.sh`.

Al final, resaltá cual de esos proyectos es el que corresponde al repo donde
esta parado el usuario ahora mismo (comparando contra `git remote get-url
origin`), y si el repo actual **no** aparece en el listado, decilo
explicitamente en vez de dejarlo implicito.

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

Usa esto (sin deployar) cuando el usuario invoca el skill **sin especificar
entorno** (`/mantis_deploy` a secas, "deployar", "que entornos tiene esto",
"estado del ultimo build"). Mostrale los entornos disponibles y esperá a que
elija uno antes de tocar `deploy.sh`.

Deployar y esperar el resultado final:

```bash
~/.claude-most/skills/mantis_deploy/scripts/deploy.sh test --wait
```

**Si el usuario invoca el skill con el entorno explicito** (`/mantis_deploy
test`, "deployar a test", "subir a demo"), **eso ya es la confirmacion** — no
le vuelvas a preguntar "¿confirmas?" en el chat. La secuencia es siempre estos
tres pasos, uno atras del otro, sin pausa a esperar el ok del usuario entre el
1 y el 2:

1. **Mostra la info del deploy** (a modo informativo, no como gate): proyecto
   detectado, entorno, job de Jenkins y rama que va a construir (y si el
   script previamente aviso cambios sin commitear/pushear o rama distinta a
   la esperada — regla 3 — ahi si frena y pregunta antes de seguir).
2. **Ejecuta el deploy automaticamente**: `deploy.sh <entorno> --wait`.
3. **Esperá el resultado final y comunicaselo**: el script sondea Jenkins
   hasta que el build termina, imprime `Resultado: SUCCESS|FAILURE|ABORTED|...`
   y sale con codigo 0 solo si fue `SUCCESS`. Comunicale ese resultado al
   usuario tal cual (no alcanza con pasar la URL de cola) y segui distinto
   segun el caso:

- **SUCCESS**: confirmalo. Si el usuario quiere ver el resultado, el skill
  `mantis_preview` abre el entorno de test en Chrome.
- **FAILURE / ABORTED / UNSTABLE**: decilo explicitamente y ofrece revisar la
  consola (la URL que imprime el script). No reintentes el deploy por tu
  cuenta.

Para entornos con `confirm: true` (tipicamente `release`) esto no cambia nada:
la confirmacion tipeada la sigue pidiendo el script mismo (regla 1), no es un
gate de chat y no se puede saltear pasando el nombre de entorno.

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
2. Si el usuario invoca el skill con el entorno explicito (`/mantis_deploy
   test`, "deployar a test", "subir a demo"), eso YA es la confirmacion — no
   se pregunta de nuevo en el chat. Mostrale a modo informativo el proyecto,
   entorno, job y rama detectados, y andá directo a `deploy.sh <entorno>
   --wait`, esperando el resultado final para reportarlo. Si el usuario NO
   especifico entorno (`/mantis_deploy` a secas, "deployar", "que entornos
   tiene esto"), corre `status.sh`, mostrale los entornos disponibles y
   esperá a que elija uno antes de deployar. En ambos casos, para entornos
   con `confirm: true` (tipicamente `release`) sigue rigiendo la confirmacion
   tipeada dentro del script (regla 1) — eso nunca se saltea.
3. Si el script avisa que hay cambios sin commitear, commits sin pushear, o que
   la rama no coincide con la esperada, **frena y preguntale al usuario** antes
   de seguir. Jenkins construye lo que esta en el remote, no lo que hay local.
4. Produccion no se deploya desde aca. Los jobs `PROD-*` estan declarados en
   `blocked` y el script los rechaza incluso si alguien pasa el nombre a mano.
   Si el usuario pide produccion, explicale que ese camino va por el proceso
   manual del equipo de infraestructura.
5. Si el repo no esta mapeado en `projects.json`, **no inventes nombres de
   jobs**: mostrale el `listado` (ver seccion de arriba) para que vea que otros
   repos si estan configurados, corre `discover.sh --suggest <CARPETA>`,
   mostrale el bloque JSON al usuario y proponele agregarlo al repo
   `most-agent` (asi lo hereda todo el equipo con un `git pull`).
6. Reporta siempre la URL de consola que devuelve el script — es lo que el
   usuario va a querer abrir.
7. Si el job falla, ofrece revisar la consola; no vuelvas a disparar el deploy
   sin que el usuario lo pida.
8. Para mostrar visualmente el resultado en test (abrir el sitio en Chrome),
   usa el skill `mantis_preview` — no repliques esa logica aca.
9. Nunca corras `git`/commit/push contra `~/.claude-most/brain` a mano: el
   unico camino permitido es `~/.claude-most/bin/brain-publish.sh` (ver
   "Registrar el resultado en el company brain" mas arriba).
10. `/mantis_deploy listado` es de solo lectura (Read sobre `projects.json`,
    ningun script, ningun request a Jenkins) — se puede mostrar siempre, sin
    credenciales ni confirmacion, incluso si el repo actual no esta mapeado.

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
