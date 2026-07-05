# Configurar Google OAuth en ARCHITECT

Guía paso a paso para habilitar **Iniciar sesión con Google** y **Registrarse con Google**.

## Requisitos

- Cuenta de Google (Gmail o Google Workspace)
- ARCHITECT corriendo localmente o en un dominio con HTTPS (producción)

---

## Paso 1 — Crear proyecto en Google Cloud

1. Abre [Google Cloud Console](https://console.cloud.google.com/).
2. Arriba a la izquierda, clic en el selector de proyectos → **Nuevo proyecto**.
3. Nombre sugerido: `ARCHITECT` → **Crear**.
4. Espera unos segundos y selecciona ese proyecto.

---

## Paso 2 — Pantalla de consentimiento OAuth

1. Menú ☰ → **APIs y servicios** → **Pantalla de consentimiento de OAuth**.
2. Tipo de usuario:
   - **Externo** (para cualquier cuenta Gmail) — recomendado en desarrollo.
   - **Interno** solo si usas Google Workspace de tu organización.
3. Clic en **Crear**.
4. Completa:
   - **Nombre de la aplicación:** `ARCHITECT`
   - **Correo de asistencia:** tu correo
   - **Correo del desarrollador:** tu correo
5. **Guardar y continuar**.
6. En **Ámbitos (Scopes)** → **Añadir o quitar ámbitos** y agrega:
   - `.../auth/userinfo.email`
   - `.../auth/userinfo.profile`
   - `openid`
7. **Guardar y continuar** hasta finalizar.
8. En desarrollo, en **Usuarios de prueba**, añade tu correo si la app está en modo "Prueba".

---

## Paso 3 — Crear credenciales OAuth 2.0

1. Menú ☰ → **APIs y servicios** → **Credenciales**.
2. **+ Crear credenciales** → **ID de cliente de OAuth**.
3. Tipo de aplicación: **Aplicación web**.
4. Nombre: `ARCHITECT Web`.

### URIs de redirección autorizadas

Añade **exactamente** la URL del callback de tu entorno:

| Entorno | URI de redirección |
|---------|-------------------|
| Local (`python app.py`, puerto 8080) | `http://127.0.0.1:8080/api/auth/google/callback` |
| Docker backend (puerto 8000) | `http://localhost:8000/api/auth/google/callback` |
| Producción | `https://tudominio.com/api/auth/google/callback` |

5. Clic en **Crear**.
6. Copia el **ID de cliente** y el **Secreto del cliente**.

---

## Paso 4 — Variables en `.env`

```env
APP_BASE_URL=http://127.0.0.1:8080
GOOGLE_CLIENT_ID=123456789-xxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-xxxxxxxx
```

### Cómo elegir `APP_BASE_URL`

| Cómo corres ARCHITECT | `APP_BASE_URL` |
|----------------------|----------------|
| `python app.py` (puerto 8080) | `http://127.0.0.1:8080` |
| Docker: frontend Vite :3000 | `http://localhost:3000` |
| Producción | `https://tudominio.com` |

---

## Paso 5 — Migrar base de datos

```bash
python scripts/init_db.py
```

---

## Paso 6 — Reiniciar y probar

1. Reinicia el servidor backend.
2. Abre `/login` — debe aparecer **Continuar con Google**.

---

## Solución de problemas

| Error | Solución |
|-------|----------|
| `redirect_uri_mismatch` | URI en Google debe coincidir exactamente con el callback |
| Botón no aparece | Revisa `GOOGLE_CLIENT_ID` y `GOOGLE_CLIENT_SECRET` en `.env` |
| `403 access_denied` | Añade tu correo en Usuarios de prueba (modo Prueba) |
