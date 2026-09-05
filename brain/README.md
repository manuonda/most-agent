# Company Brain

Memoria compartida del equipo sobre el trabajo hecho en Mantis: qué se hizo, qué se testeó, qué se decidió, y en qué quedó cada issue. Pensado para responder, sin abrir Mantis ni buscar en un worktree que ya puede no existir, preguntas como "¿cómo quedó el mantis 1234?" o "¿qué se hizo ahí?".

## Por qué existe

`mantis_develop` y `mantis_comment` ya generaban un resumen de cada sesión de trabajo, pero quedaba en un lugar efímero y local al repo/worktree que se estaba usando (`.claude/mantis-sessions/<N>.md`), con una ruta distinta según en qué proyecto Most estuviera parado el developer. Al borrarse el worktree, se perdía. El Brain resuelve eso: la nota vive siempre en la misma ruta (`~/.claude-most/brain/`, symlink al `brain/` de este repo), sin importar el proyecto/repo activo.

## Inspiración (y por qué NO copiamos esa arquitectura)

La idea nace de un post sobre GuruSup Brain (segundo cerebro empresarial tipo SaaS): ellos curan el conocimiento en markdown pero lo sirven desde Postgres+pgvector (búsqueda vectorial) + Memgraph (grafo de entidades) + Mongo (capa aplicativa), con BM25 + reranking en la consulta, expuesto vía MCP a distintos clientes LLM. Esa infraestructura resuelve un problema de volumen y multi-tenencia (muchos clientes externos consultando en simultáneo) que no es el nuestro.

Para el equipo de Grupo Most, con el volumen de Mantis que manejamos, markdown + grep alcanza — no hace falta vector DB ni grafo. Dos ideas de ese enfoque sí valen la pena y las aplicamos igual, sin la infraestructura pesada:

- Separar la fuente de verdad curada (la nota del brain) de la fuente en crudo (el issue de Mantis, la conversación de desarrollo).
- Ante una contradicción entre lo que dice el brain y el estado real del issue, no inventar: la consulta siempre revalida contra la API de Mantis en vivo antes de contestar.

## Estructura

```
brain/
└── mantis/
    └── <proyecto>/          # slug de issues[0].project.name (minúsculas, espacios -> guiones)
        └── <N>.md           # una nota por issue de Mantis
```

Cada nota tiene este formato:

```markdown
---
mantis: <N>
proyecto: <nombre del proyecto en Mantis>
estado: <en_progreso | resuelto | cerrado>
fecha_actualizacion: <YYYY-MM-DD>
---

## Qué se hizo
...

## Notas de testing / pendientes
...

## Resumen enviado a Mantis
(texto de la última nota posteada por mantis_comment, si existe)
```

## Cómo se llena y se consulta

- La escribe/actualiza automáticamente `mantis_develop` (al cerrar una sesión de trabajo) y `mantis_comment` (al postear una nota a Mantis). Ver los `SKILL.md` de cada una.
- Se consulta con la skill `company_brain`: `/company_brain <issue>`, o preguntando directamente "¿cómo quedó el mantis X?" / "qué se hizo en el mantis X".

## Sync entre developers (importante)

Esta carpeta vive en este repo (`most-agent`), compartido por todo el equipo vía git, pero el commit/push **es manual y explícito** — ninguna skill lo hace por su cuenta. Para que otro developer o analista vea tu nota:

1. Vos tenés que pedir explícitamente publicarla (`/company_brain publicar <N>`, o "subí la nota del mantis X al brain").
2. La otra persona ve lo último apenas consulta, porque `company_brain` (y el paso 1 de `mantis_comment`) hacen `git pull` antes de leer.

Si nunca se pide publicar, la nota queda solo en tu máquina.
