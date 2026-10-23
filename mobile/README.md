# ARCHITECT — App móvil

App Flutter para revisar planos de arquitectura con IA, conectada a un backend FastAPI.

## Requisitos

- Flutter SDK ^3.11
- Backend FastAPI corriendo (Docker, puerto `8000`)
- Android Studio / Xcode para emulador o dispositivo físico

## Configurar la URL del servidor

La URL **no está hardcodeada** en producción. Se guarda en el dispositivo y puedes cambiarla en:

**Ajustes (ícono engranaje)** → pantalla **Servidor**

| Entorno | URL recomendada |
|--------|------------------|
| Emulador Android | `http://10.0.2.2:8000` |
| Simulador iOS | `http://localhost:8000` |
| Dispositivo físico (misma Wi‑Fi) | `http://<IP_DE_TU_PC>:8000` |

Ejemplo dispositivo físico: `http://192.168.1.50:8000`

Para obtener la IP de tu PC en Windows:

```powershell
ipconfig
```

Busca `Dirección IPv4` de tu adaptador Wi‑Fi.

## Credenciales de prueba

- **Email:** `admin@architect.local`
- **Password:** `admin123`

## Ejecutar la app

```bash
flutter pub get
flutter run
```

Asegúrate de que el backend responda en `/api/mobile/health` antes de iniciar sesión.

## Flujo de la aplicación

1. **Splash** — `GET /api/mobile/health`
2. Si hay token válido → `GET /api/mobile/me` → Dashboard
3. Si no hay token → Login
4. **Login** — `POST /api/auth/login` → guarda JWT en almacenamiento seguro
5. **Dashboard** — perfil, plan, historial (`GET /api/analyses`)
6. **Casa hogar** — menú lateral → proyectos de vivienda (9 etapas)
7. **Analizar plano** — cámara, galería o archivo → `POST /api/mobile/analyze`
8. **Resultados** — veredicto, contadores, imagen anotada e incidencias

## Casa hogar (MVP)

Módulo de proyectos de vivienda unifamiliar. Requiere JWT (mismo login).

### API base

Prioridad:
1. `--dart-define=API_BASE=...`
2. URL guardada en Ajustes
3. Default actual (Cloudflare Tunnel): `https://arkansas-vision-custom-sunday.trycloudflare.com`

```bash
flutter run --dart-define=API_BASE=https://arkansas-vision-custom-sunday.trycloudflare.com
flutter build apk --release --dart-define=API_BASE=https://arkansas-vision-custom-sunday.trycloudflare.com
```

El APK queda en:
`build/app/outputs/flutter-apk/app-release.apk`

JWT: el interceptor de `ApiClient` sigue enviando `Authorization: Bearer <token>`.

Endpoints (base + path, sin slash doble):
- `{API_BASE}/api/health`
- `{API_BASE}/api/auth/login`
- `{API_BASE}/api/home-projects`
- etc.

Endpoints consumidos (todos con `Authorization: Bearer <token>`):

| Método | Ruta |
|--------|------|
| GET/POST | `/api/home-projects` |
| GET/PATCH/DELETE | `/api/home-projects/{id}` |
| PATCH | `/api/home-projects/{id}/sections/{sectionId}` |
| GET/POST/DELETE | `/api/home-projects/{id}/sections/{sectionId}/comments` |
| POST/DELETE | `/api/home-projects/{id}/members/...` |
| POST | `/api/home-projects/invites/accept` |
| POST | `/api/home-projects/{id}/stages/{n}/assist` |
| GET | `/api/home-projects/analyses-picker` |
| PATCH | `/api/home-projects/{id}/stages/{n}` (`analysis_id`) |
| POST | `/api/home-projects/{id}/stages/{n}/documents` |
| GET/DELETE | `/api/home-projects/{id}/documents/{docId}` (+ `/file`) |
| POST | `/api/home-projects/{id}/advance` |

Extras del MVP+:
- Comentarios en apartados
- Equipo / invitaciones (ícono en detalle + aceptar token en lista)
- Asistencia IA por etapa
- Vincular planos (etapas con `plan_review`)

### Cómo probar

1. Backend en `:8000` y app apuntando a tu `API_BASE`
2. Login con `admin@architect.local` / `admin123`
3. Menú → **Casa hogar**
4. Crear proyecto → abrir etapa → apartado → subir documento / cambiar estado
5. **Avanzar etapa** solo si `permissions.can_advance_stage == true`

Archivos principales:

- `lib/models/home_project_models.dart`
- `lib/services/home_project_service.dart`
- `lib/controllers/home_project_controller.dart`
- `lib/views/home_projects/`

## Arquitectura (MVC)

```
lib/
├── core/          # Config, red (Dio), almacenamiento
├── models/        # Modelos de API
├── services/      # AuthService, MobileApiService
├── controllers/   # Lógica de pantallas
└── views/         # UI
```

## Cliente HTTP

- **Dio** con `baseURL` configurable
- Interceptor que añade `Authorization: Bearer <token>`
- Interceptor **401** → borra token y redirige a Login

## Probar en dispositivo físico

1. Backend en Docker: `puerto 8000` expuesto
2. PC y móvil en la **misma red Wi‑Fi**
3. En la app: **Ajustes → Servidor** → `http://TU_IP:8000`
4. Pulsa **Probar conexión**
5. Inicia sesión con las credenciales de prueba

## Endpoints usados

| Método | Ruta | Auth |
|--------|------|------|
| GET | `/api/mobile/health` | No |
| POST | `/api/auth/login` | No |
| POST | `/api/auth/register` | No |
| GET | `/api/mobile/me` | Sí |
| GET | `/api/analyses?limit=20` | Sí |
| POST | `/api/mobile/analyze` | Sí |

## Solución de problemas

- **No se pudo conectar al servidor** → revisa URL, firewall y que Docker esté activo
- **401 al analizar** → sesión expirada; vuelve a iniciar sesión
- **402** → límite mensual de análisis alcanzado
- **413** → archivo demasiado grande según tu plan
