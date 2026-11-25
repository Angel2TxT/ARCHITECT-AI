# Reporte de Prueba Automatizada — MOV-006

| Campo | Información |
|---|---|
| ID | MOV-006 |
| Nombre | El estado de una etapa no cambia al seleccionarlo |
| Tipo | Funcional |
| Prioridad | Alta |
| Herramienta | Patrol (`patrol: ^4.12.0`, `patrol_cli: 4.10.0`) |
| Dispositivo | Emulador Android (`emulator-5554`, `Pixel_10_Pro(AVD) - 17`) |
| Resultado | **Fallido** (defecto real reproducido) |
| Evidencias | [screenshots/01_estado_inicial_pendiente.png](screenshots/01_estado_inicial_pendiente.png), [screenshots/02_selector_estados.png](screenshots/02_selector_estados.png), [screenshots/03_despues_seleccionar_en_progreso.png](screenshots/03_despues_seleccionar_en_progreso.png), [logs/patrol_run.log](logs/patrol_run.log), [logs/backend_requests.log](logs/backend_requests.log) |
| Observaciones | Al seleccionar **«En progreso»** en el selector de estados, el backend responde `403 Forbidden` y el apartado **«Necesidades del cliente»** permanece en **«Pendiente»** tanto en la UI como en MySQL. |

---

## 1. Datos de prueba utilizados

- **Usuario de prueba:** `cliente.qa@architect.local` (`role: user`, miembro `editor` del proyecto `UTS`).
- **Proyecto:** `UTS` (`1323d864-b516-4db9-bfc5-8cd1e2afcacc`).
- **Etapa / Apartado:** Etapa 1 (`Programación`) → Apartado `Necesidades del cliente` (`section_id: 55`).
- **Estado inicial verificado:** `Pendiente` (`pending`).
- **Estado objetivo seleccionado:** `En progreso` (`in_progress`).

---

## 2. Pasos ejecutados por Patrol

1. Inicio de la app en `emulator-5554` y autenticación con `cliente.qa@architect.local`.
2. Apertura del menú lateral → `Casa hogar` → proyecto `UTS` → apartado `Necesidades del cliente`.
3. Verificación del estado inicial `Pendiente` ([01_estado_inicial_pendiente.png](screenshots/01_estado_inicial_pendiente.png)).
4. Tap en `Cambiar estado` y verificación del selector `Estado del apartado` con las opciones disponibles ([02_selector_estados.png](screenshots/02_selector_estados.png)).
5. Tap en `En progreso`.
6. Espera de respuesta del backend y verificación de estado en pantalla ([03_despues_seleccionar_en_progreso.png](screenshots/03_despues_seleccionar_en_progreso.png)).
7. La aserción en `mov_006_change_stage_status_test.dart:53` falló porque el estado siguió siendo `Pendiente` y nunca cambió a `En progreso`.

---

## 3. Causa raíz detectada

1. **Inconsistencia de permisos entre UI móvil y backend:**
   - La app móvil (`SectionDetailView`) muestra el botón `Cambiar estado` y abre el selector `Estado del apartado` basándose en `permissions.canEdit` (que es `true` para un miembro `editor`).
   - Al seleccionar `En progreso`, la app envía `PATCH /api/home-projects/1323d864-b516-4db9-bfc5-8cd1e2afcacc/sections/55` con `{"status": "in_progress"}`.
   - El backend (`backend/services/home_project_service.py:1746-1747`) rechaza la petición con **`403 Forbidden`** mediante `_require_unassigned_section_owner(section, actor_role)` cuando el apartado no está asignado al usuario `editor` (y además en la línea `1787` exige documentos cargados para pasar de `pending` a otro estado si no es `admin`).
2. **Resultado en UI y base de datos:**
   - El estado en `home_project_sections` (`id=55`) permanece en `pending` y la píldora en pantalla continúa mostrando `Pendiente`.
   - *(No se modificó el código de producción para ocultar el defecto).*

---

## 4. Cómo volver a ejecutar la prueba

Desde `mobile/` con el backend Docker arriba y `emulator-5554` conectado:

```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
patrol test --no-uninstall `
  -t patrol_test/mov_006/mov_006_change_stage_status_test.dart `
  -d emulator-5554 `
  --dart-define=TEST_EMAIL=cliente.qa@architect.local `
  --dart-define=TEST_PASSWORD=QaTest1234! `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000
```
