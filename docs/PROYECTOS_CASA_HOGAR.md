# Proyectos casa hogar — 9 etapas

Administración de proyectos de **vivienda unifamiliar** siguiendo la metodología de diseño en 9 fases (programación → entrega).

Casa hogar es un **expediente**: entregables, revisión del equipo, archivos y actividad. La IA es **apoyo embebido**, no el producto.

## Uso sin conexión

Tras abrir Casa hogar **al menos una vez con internet** (PWA o `/legacy-app`):

- La **sesión JWT** permanece en el dispositivo; un fallo de red no te cierra la sesión.
- Los proyectos se cachean en **IndexedDB**; puedes navegar las **9 etapas**, editar notas/estado y encolar subidas de archivos.
- Al recuperar red, la cola se sincroniza sola.
- **IA** (asistente y revisión de planos) queda bloqueada offline: requiere API.

## Etapas

| # | Etapa | Asistente (dudas) | Revisión de plano IA |
|---|--------|-------------------|----------------------|
| 1 | Programación | Sí | No |
| 2 | Investigación | Sí | No |
| 3 | Esquematización | Sí | No |
| 4 | Anteproyecto | Sí | Opcional (planta 2D) |
| 5 | Proyecto arquitectónico | Sí | Sí (habitabilidad / vanos) |
| 6 | Proyecto ejecutivo | Sí | Sí (solo lo medible en planta) |
| 7 | Presupuesto y programación | Sí | No |
| 8 | Construcción | Sí | No |
| 9 | Entrega y evaluación | Sí | No |

El catálogo editable está en `config/home_stages.yaml` (`ai_ask`, `ai_plan_review`, `ai_plan_scope`).

## Apartados y slots de archivo

Cada etapa define **apartados** (`sections`). Dentro de cada apartado, los archivos **no se mezclan**: hay **slots nombrados** (p. ej. Brief, Fotos del predio, Planta arquitectónica).

- `slots[].key` / `title`: identificador y etiqueta del entregable
- `slots[].accept`: extensiones permitidas
- `slots[].required`: si falta, el apartado no cuenta como documentalmente completo
- Upload: `POST .../stages/{n}/documents` con `section_id` + `slot_key`
- Agregar espacio: `POST .../sections/{id}/slots` (`title`, opcional `accept` / `required`)
- Quitar espacio: `DELETE .../sections/{id}/slots/{slot_key}` (borra también sus archivos)
- Eliminar apartado: `DELETE .../sections/{id}` (catálogo: solo propietario; apartados propios: también editor)

Proyectos antiguos: al abrirlos se intenta rellenar `slots_json` emparejando el título del apartado con el catálogo.

## Dos tipos de «revisión» (no confundir)

| Tipo | Quién | Qué hace |
|------|--------|----------|
| **Revisión del equipo** | Humanos en el apartado | Estados: pendiente → en curso → observaciones / corrección → correcto. Comentarios y responsables. |
| **Asistente IA** | Sistema | (1) Preguntas con contexto de etapa. (2) Revisión de **planta 2D** (imagen/PDF) con alcance explícito. |

### Alcance de la revisión de plano

Alcance activo: **`planta_integral_2d`**.

**Cubre (automático en planta):** puertas/ventanas/muros/recintos; habitabilidad; vanos; circulación; heurísticas baño/cocina/recámara/estancia; muros; superficie estimada; **guía de corrección** por hallazgo.

**Cubre (checklist, no detección):** accesibilidad, escaleras, instalaciones, eléctrico, estructura, protección civil, alturas libres (cortes).

**No cubre aún (hace falta reentrenar YOLO):** clases tipadas (`stair`, `bathroom`, `kitchen`, `column`, etc.). Ver `docs/ENTRENAMIENTO_PLANOS.md`.

Cada revisión se guarda como paquete `HomeProjectAiReview` ligado a `section_id` + `document_id` + `analysis_id`, con hallazgos accionables (aceptar / descartar) y pasos `fix` / `fix_steps`.

## API

Prefijo: `/api/home-projects` (requiere JWT).

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/catalog` | Catálogo de las 9 etapas (+ flags IA) |
| GET | `/` | Listar proyectos del usuario |
| POST | `/` | Crear proyecto (genera 9 etapas + apartados) |
| GET | `/{id}` | Detalle con etapas, `ai_reviews`, `open_ai_findings` |
| PATCH | `/{id}` | Actualizar datos generales |
| DELETE | `/{id}` | Eliminar proyecto |
| PATCH | `/{id}/stages/{n}` | Notas, checklist, estado, `analysis_id` |
| POST | `/{id}/stages/{n}/assist` | Orientación IA para la etapa (con disclaimer de alcance) |
| POST | `/{id}/stages/{n}/documents` | Subir archivo a un apartado (`section_id`) y slot (`slot_key`) |
| PATCH | `/{id}/ai-reviews/{rid}/findings/{fid}` | `accept` \| `dismiss` \| `reopen` |
| POST | `/{id}/advance` | Completar etapa; si hay hallazgos IA abiertos → `409` hasta `acknowledge_open_findings: true` |

## Flujo de IA por etapa

1. **Preguntar** — chatbot flotante (botón «IA») o desde el apartado: **Orientarme**.
2. **Sugerir comentario** — en la decisión del equipo, borrador según la acción elegida (sin leer el PDF).
3. **Revisar plano** — si hay imagen/PDF de planta en etapas con `ai_plan_review`: botón en el apartado.
4. **Avanzar** — si quedan hallazgos abiertos, el UI avisa; el despacho puede avanzar igual.

## UI

En la app legacy (`/legacy-app`): menú lateral **Casa hogar**.

## Base de datos

Tablas: `home_projects`, `home_project_stages`, `home_project_sections`, `home_project_documents`, `home_project_members`, `home_project_events`, **`home_project_ai_reviews`**.

Tras actualizar el código:

```powershell
python scripts/init_db.py
```
