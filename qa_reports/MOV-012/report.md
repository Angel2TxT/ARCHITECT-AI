# Reporte de Prueba Automatizada — MOV-012

| Campo | Información |
|---|---|
| ID | MOV-012 |
| Nombre | Registro de nombre y correo con etiquetas HTML |
| Tipo | Funcional |
| Prioridad | Media |
| Sprint | 4 |
| Herramienta | Patrol (`patrol: ^4.12.0`, `patrol_cli: 4.10.0`) |
| Dispositivo | Emulador Android (`emulator-5554`, `Pixel_10_Pro(AVD) - 17`) |
| Resultado | **PASS** |
| Evidencias | [screenshots/mov012_01_formulario_registro.png](screenshots/mov012_01_formulario_registro.png), [screenshots/mov012_03_perfil_registrado.png](screenshots/mov012_03_perfil_registrado.png), [logs/patrol_run.log](logs/patrol_run.log) |
| Observaciones | Los `FilteringTextInputFormatter.allow` de `RegisterView` eliminaron `<`, `/` y `>` al ingresar `<b>prueba</b>` y `<b>prueba</b>39422@gmail.com`, almacenando y mostrando `bpruebab` y `bpruebab39422@gmail.com` en el perfil sin etiquetas HTML ni interpretación como código. |

---

## 1. Reglas de negocio verificadas en el código

- **Frontend móvil ([register_view.dart](../../mobile/lib/views/register/register_view.dart)):**
  - Nombre (`NOMBRE COMPLETO (OPCIONAL)`): `FilteringTextInputFormatter.allow(RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]'))`.
  - Correo (`CORREO ELECTRÓNICO`): `FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9@._+-]'))`.
- **Controlador móvil ([register_controller.dart](../../mobile/lib/controllers/register_controller.dart)):**
  - Valida que el nombre solo contenga letras y espacios (`^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]+$`).
- **Ambigüedad documentada en backend ([schemas.py](../../backend/api/schemas.py)):**
  - `RegisterRequest` no valida explícitamente caracteres `<` o `>` en `email` o `full_name` si se enviaran directo al API sin pasar por la UI móvil.

---

## 2. Resultado de ejecución real

- **Entrada enviada en UI:** nombre `<b>prueba</b>`, correo dinámico `<b>prueba</b>39422@gmail.com`.
- **Valor resultante en formulario y perfil:** nombre `bpruebab`, correo `bpruebab39422@gmail.com`.
- **Aserciones:** ninguna etiqueta HTML (`<` o `>`) quedó almacenada ni interpretada en `ProfileView`.
- **Estado final:** **PASS** (1/1 prueba aprobada en 46s).

---

## 3. Comando para ejecutar individualmente

```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
cd mobile
patrol test --no-uninstall `
  -t patrol_test/mov_012/mov_012_html_tags_registration_test.dart `
  -d emulator-5554 `
  --dart-define=TEST_PASSWORD=QaTest1234! `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000
```
