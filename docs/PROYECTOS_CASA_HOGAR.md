# Proyectos casa hogar — 9 etapas

Administración de proyectos de **vivienda unifamiliar** siguiendo la metodología de diseño en 9 fases (programación → entrega).

## Etapas

| # | Etapa | Enfoque |
|---|--------|---------|
| 1 | Programación | Necesidades, objetivos, espacios |
| 2 | Investigación | Terreno, clima, normativa |
| 3 | Esquematización | Diagramas, zonificación |
| 4 | Anteproyecto | Bocetos y plantas preliminares |
| 5 | Proyecto arquitectónico | Planos completos + revisión IA |
| 6 | Proyecto ejecutivo | Constructivo, instalaciones, estructura |
| 7 | Presupuesto y programación | Costos y cronograma |
| 8 | Construcción | Supervisión y calidad |
| 9 | Entrega y evaluación | Cierre y punch list |

El catálogo editable está en `config/home_stages.yaml`.

## API

Prefijo: `/api/home-projects` (requiere JWT).

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/catalog` | Catálogo de las 9 etapas |
| GET | `/` | Listar proyectos del usuario |
| POST | `/` | Crear proyecto (genera 9 etapas + checklist) |
| GET | `/{id}` | Detalle con etapas |
| PATCH | `/{id}` | Actualizar datos generales |
| DELETE | `/{id}` | Eliminar proyecto |
| PATCH | `/{id}/stages/{n}` | Notas, checklist, estado |
| POST | `/{id}/stages/{n}/assist` | Orientación IA para la etapa |
| POST | `/{id}/advance` | Completar etapa actual y avanzar |

## IA por etapa

`POST .../assist` arma un contexto con nombre del proyecto, ubicación, etapa, checklist pendiente y notas. Usa el mismo motor que `/api/ask` (manuales indexados + umbrales Chiapas + web opcional).

En etapas **5** y **6** se sugiere vincular la revisión de planos del Workspace.

## UI

En la app legacy (`/legacy-app`): menú lateral **Casa hogar**.

## Base de datos

Tablas: `home_projects`, `home_project_stages`.

Tras actualizar el código:

```powershell
python scripts/init_db.py
```
