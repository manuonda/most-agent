---
name: mantis_preview
description: "Abre en Chrome el entorno de test del proyecto actual para mostrar visualmente los cambios recien deployados. Resuelve el proyecto por el remote git (igual que mantis_deploy) y obtiene la URL desde la description del job TEST-* en Jenkins, sin URLs hardcodeadas. Por ahora solo entorno test (demo/release quedan para mas adelante). Trigger: /mantis_preview, 'mostrame los cambios en test', 'abri test en el navegador', 'abrime test en chrome', 'quiero ver como quedo en test'."
---

# Mantis Preview — abrir test en Chrome

Complementa a `mantis_deploy`: abre el entorno de **test** del proyecto actual
en Chrome, usando el skill `claude-in-chrome`, para que el developer vea
visualmente los cambios sin salir del chat.

No dispara nada en Jenkins ni en el proyecto: solo lee una URL y navega a
ella.

## Como se resuelve la URL

1. Corre:

   ```bash
   ~/.claude-most/skills/mantis_preview/scripts/preview-url.sh
   ```

   Este script reusa la config y las credenciales de `mantis_deploy`
   (`config/projects.json`, `jenkins-api.sh`) para identificar el proyecto por
   el remote git y consulta la Jenkins API del job `TEST-*` correspondiente.
   La URL **no esta hardcodeada en ningun lado**: se lee de la "description"
   del job en Jenkins (ahi el equipo ya la deja publicada, ej.
   `https://test-geins-ypf.grupomost.com/most-geins`), asi que si cambia en
   Jenkins se refleja sola, sin tocar este repo.

2. Con la URL, usa las herramientas de `claude-in-chrome` para navegar a esa
   direccion en una pestaña nueva y, si tiene sentido para lo que pidio el
   usuario, sacar un screenshot para mostrarselo en el chat.

## Alcance (por ahora)

- **Solo `test`.** El equipo trabaja exclusivamente contra ese entorno por el
  momento; no ofrezcas abrir `demo` o `release` aunque el proyecto los tenga
  configurados en `mantis_deploy`.
- Es un skill independiente de `mantis_deploy` — no se dispara solo despues de
  un deploy, se invoca cuando el usuario lo pide.

## Prerequisitos

- Mismas credenciales que `mantis_deploy` (`JENKINS_USER` / `JENKINS_API_TOKEN`
  bajo `env`), porque reusa su `jenkins-api.sh`.
- El proyecto tiene que estar mapeado en `config/projects.json` de
  `mantis_deploy` con el job de `test` ya configurado (no `TODO-*`).
- El job de Jenkins de `test` tiene que tener la URL publicada en su
  "Description" (Configure > Description en Jenkins). Si no la tiene, el
  script lo va a decir explicitamente — no inventes ni asumas una URL.
- Extension `claude-in-chrome` habilitada con permiso sobre el sitio de test.

## Reglas

1. **Nunca inventes ni hardcodees la URL de test.** Si `preview-url.sh` falla
   porque el job no tiene description, decile al usuario que la agregue en
   Jenkins — no la completes a mano ni la busques por otro lado.
2. Antes de abrir Chrome, mostra la URL que vas a visitar y a que proyecto
   corresponde, asi el usuario sabe que va a ver.
3. Si el usuario pide `demo` o `release`, explicale que por ahora el flujo de
   preview solo cubre `test`.
4. No completes formularios de login ni manipules credenciales dentro del
   sitio sin que el usuario lo pida explicitamente — el objetivo es solo
   mostrar el estado visual, no operar la app.

## Errores comunes

- **`no esta mapeado en config/projects.json`**: correr
  `~/.claude-most/skills/mantis_deploy/scripts/discover.sh` primero (ver skill
  `mantis_deploy`).
- **`no tiene una URL publicada en su descripcion`**: pedirle al equipo que la
  agregue en el job de Jenkins (Configure > Description).
- **`no se encontro jenkins-api.sh`**: falta instalar/actualizar. Desde el
  clon de `most-agent`: `git pull && ./install.sh`.
