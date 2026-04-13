# Output Status Codes

This simulator uses one explicit status vocabulary for browser-owned LLS/coupled-runtime outputs.

## Classification Codes

| Code | Meaning | Policy |
| --- | --- | --- |
| `a` | Not implemented in simulator backend | Show as unavailable with required source block, capture point, next step, and backlog owner. Do not create fake rows or fake artifact files. |
| `c` | Present in backend but not persisted | Persist the existing backend data into canonical DB-backed CSV/JSON artifacts and expose row-count checks. |
| `d` | Present in backend and persisted but not exposed by API | Keep backend unchanged and expose through `/api/run/<id>/live`, browser cards, and export links. |
| `f` | Schema-only or placeholder-only | Keep UI/schema visible but mark `schema_only` unless real runtime rows exist. |
| `r` | Runtime prerequisite not satisfied | Gate the view until comparable run groups, metric harmonization, or alignment prerequisites are present. |

## UI Status Values

| Status | Meaning |
| --- | --- |
| `implemented` | Runtime-backed or honestly derived rows exist and are persisted canonically. |
| `partial` | Some real rows or APIs exist, but coverage is incomplete and the missing part is labeled. |
| `unavailable` | Backend source is absent; registry explains the exact source block and next task. |
| `schema_only` | Schema exists, but no runtime-backed rows should be shown yet. |
| `blocked` | Runtime prerequisite is not satisfied for this run. |

Unavailable outputs are manifest/audit metadata only. They must not create synthetic primary CSV rows.
