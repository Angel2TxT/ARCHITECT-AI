# ARCHITECT

Plataforma para revisar planos de arquitectura y responder consultas de construcción. Combina **FastAPI**, **React**, detección **YOLO**, **reglas normativas** (Chiapas), **biblioteca de manuales PDF**, billing demo, proyectos casa hogar y flujo de invitado.

---

## App móvil (Flutter)

Cliente Android/iOS conectado al mismo backend. Código y documentación:

**[https://github.com/Arcogo12/movil-Architect](https://github.com/Arcogo12/movil-Architect)**

```powershell
git clone https://github.com/Arcogo12/movil-Architect.git
cd movil-Architect
flutter pub get
flutter run
```

Requisitos: Flutter SDK ^3.11, backend ARCHITECT en el puerto **8000**. En la app, **Ajustes → Servidor**:

| Entorno | URL del backend |
|---------|-----------------|
| Emulador Android | `http://10.0.2.2:8000` |
| Simulador iOS | `http://localhost:8000` |
| Dispositivo físico (misma Wi‑Fi) | `http://<IP_DE_TU_PC>:8000` |

Credenciales de prueba: `admin@architect.local` / `admin123`.

---

## Requisitos

| Modo | Necesitas |
|------|-----------|
| **Docker (recomendado)** | Docker Desktop, Git |
| **Local sin Docker** | Python 3.10+, Node 20+, MySQL 8 |

RAM recomendada: **8 GB** (Docker + modelo YOLO).

---

## Arranque rápido (Docker)

```powershell
cd C:\UNI\ARCHITECT
copy .env.example .env
docker compose up --build -d
```

Espera ~1–2 min la primera vez (MySQL + dependencias). El backend ejecuta `scripts/init_db.py` automáticamente.

### URLs

| Servicio | URL |
|----------|-----|
| **App principal (React)** | http://localhost:3000 |
| **App legacy (chat/planos)** | http://localhost:3000/legacy-app o http://localhost:8000/legacy-app |
| **Login** | http://localhost:3000/login |
| **API + Swagger** | http://localhost:8000/docs |
| **MySQL (desde tu PC)** | `localhost:3307` — user `architect`, pass `architect_pass`, DB `architect` |

### Credenciales de desarrollo

```text
Email:    admin@architect.local
Password: admin123
```

(Creadas por `scripts/init_db.py` con `ADMIN_EMAIL` / `ADMIN_PASSWORD` del `.env`.)

---

## Configuración `.env`

Copia la plantilla y edita lo mínimo:

```powershell
copy .env.example .env
```

| Variable | Uso |
|----------|-----|
| `APP_BASE_URL` | URL pública para correos y OAuth. Local: `http://localhost:8000`. Demo remota: URL del túnel Cloudflare. |
| `JWT_SECRET_KEY` | Secreto para sesiones (cámbialo en producción). |
| `BILLING_MODE=demo` | Pasarela simulada (proyecto escolar). Sin Stripe real. |
| `WEB_SEARCH_ENABLED=true` | Búsqueda web en consultas sin plano (DuckDuckGo). |
| `GUEST_TRIAL_*` | Límites de prueba sin cuenta (análisis, preguntas, MB). |
| `MAIL_*` | SMTP Brevo para comprobantes PDF y recuperación de contraseña. Ver [docs/MAIL_BREVO_SETUP.md](docs/MAIL_BREVO_SETUP.md). |
| `GOOGLE_CLIENT_*` | Login con Google (opcional). Ver [docs/GOOGLE_OAUTH_SETUP.md](docs/GOOGLE_OAUTH_SETUP.md). |

Tras cambiar `.env`:

```powershell
docker compose up -d --force-recreate backend
```

---

## Funcionalidades incluidas

- **Revisión de planos** — PNG, JPG, PDF, DXF, DWG → YOLO + reglas normativas.
- **IA ARCHITECT (chat sin plano)** — Responde con manuales indexados, umbrales Chiapas y web. Sin APIs de pago.
- **Prueba sin cuenta** — Cookie de invitado con límites configurables.
- **Planes y billing demo** — Checkout simulado, comprobantes PDF, historial en perfil.
- **Proyectos casa hogar** — Flujo por etapas, secciones, invitaciones.
- **Admin** — Panel de usuarios, ventas demo, comprobantes.
- **Correo** — Tickets PDF y reset de contraseña vía Brevo (opcional).
- **Google OAuth** — Opcional.

---

## Biblioteca de conocimiento (manuales PDF)

Los PDF en `data/knowledge/raw/` alimentan el chat. Ya incluidos en el entorno Docker:

- `Manual+Casa+1_LR.pdf` — Vivienda progresiva  
- `las-medidas-de-una-casa.pdf` — Tablas de medidas  
- `Neufert - parte 1.pdf` — Referencia antropométrica  

### Indexar o actualizar manuales

```powershell
docker compose exec backend python scripts/ingest_knowledge_docs.py
docker compose restart backend
```

Comprueba: `GET http://localhost:8000/api/ask/status` → `document_catalog`, `knowledge_pages`.

Guías: [docs/CONOCIMIENTO_DOCUMENTOS.md](docs/CONOCIMIENTO_DOCUMENTOS.md), [docs/CONSULTAS_CONSTRUCCION.md](docs/CONSULTAS_CONSTRUCCION.md).

---

## Modelo YOLO (detección en planos)

Sin modelo entrenado, el análisis usa el demo sintético o no detecta elementos en planos reales.

```powershell
# Demo rápido (sintético)
docker compose exec backend python scripts/train_demo.py

# Producción (planos reales, requiere dataset)
docker compose exec backend python scripts/download_dataset.py
docker compose exec backend python scripts/cubicasa_to_yolo.py --input data/raw/dataset
docker compose exec backend python scripts/train.py --epochs 50 --device cpu
```

Ver [docs/ENTRENAMIENTO_PLANOS.md](docs/ENTRENAMIENTO_PLANOS.md).

---

## Demo pública (túnel Cloudflare)

Para compartir la app sin desplegar:

```powershell
.\scripts\tunnel.ps1
```

Copia la URL `https://....trycloudflare.com`, ponla en `.env` como `APP_BASE_URL` y reinicia el backend:

```powershell
docker compose up -d --force-recreate backend
```

---

## Desarrollo local sin Docker

### Backend

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
# Edita DATABASE_URL → MySQL local (puerto 3306)
python scripts/init_db.py
python scripts/migrate.py
python -m uvicorn api.server:app --reload --port 8000
```

Alternativa con launcher local (puerto 8080):

```powershell
python app.py
```

### Frontend

```powershell
cd frontend
npm install --cache ..\.npm-cache
npm run dev
```

Proxy API: `frontend/vite.config.js` → `http://localhost:8000`.

---

## Migraciones de base de datos

Si actualizas desde una versión anterior:

```powershell
docker compose exec backend python scripts/migrate.py
```

---

## Scripts útiles

| Script | Descripción |
|--------|-------------|
| `scripts/init_db.py` | Crea tablas, seed de planes y admin |
| `scripts/migrate.py` | Migraciones incrementales |
| `scripts/ingest_knowledge_docs.py` | Indexa PDF de `data/knowledge/raw` |
| `scripts/train_demo.py` | Modelo YOLO demo |
| `scripts/tunnel.ps1` | Túnel Cloudflare → puerto 8000 |
| `scripts/test_mail.py` | Prueba SMTP Brevo |
| `scripts/test_receipt_email.py` | Prueba correo con PDF de comprobante |
| `scripts/validate_billing_e2e.py` | Prueba flujo billing demo |

---

## Estructura del proyecto

```text
frontend/          React + Vite (app nueva, :3000)
web/               App legacy chat/planos (/legacy-app)
api/               Rutas FastAPI
core/              Pipeline YOLO + análisis
services/          Auth, billing, email, IA ARCHITECT, CAD, storage
rules/             Normas Chiapas y motor de reglas
db/                Modelos SQLAlchemy, seed, migraciones
config/            Clases YOLO, etapas casa hogar
scripts/           DB, entrenamiento, ingest, utilidades
docs/              Documentación detallada
data/knowledge/    PDF raw + processed (indexados)
```

---

## Stack

- **Frontend:** React, Vite, Three.js, Tailwind  
- **Backend:** FastAPI, SQLAlchemy, PyMySQL  
- **IA:** Ultralytics YOLOv8, OpenCV, reglas en `rules/`  
- **DB:** MySQL 8  
- **Contenedores:** Docker Compose  

---

## Validación

```powershell
# Frontend
cd frontend
npm run build

# Backend
docker compose exec backend python -m compileall -q api core db rules services scripts

# Docker
docker compose config
```

---

## Documentación

| Tema | Archivo |
|------|---------|
| Equipo / onboarding | [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md) |
| MySQL | [docs/MYSQL_SETUP.md](docs/MYSQL_SETUP.md) |
| Consultas IA (sin plano) | [docs/CONSULTAS_CONSTRUCCION.md](docs/CONSULTAS_CONSTRUCCION.md) |
| Manuales PDF | [docs/CONOCIMIENTO_DOCUMENTOS.md](docs/CONOCIMIENTO_DOCUMENTOS.md) |
| Normas Chiapas | [docs/NORMAS_CHIAPAS.md](docs/NORMAS_CHIAPAS.md) |
| Billing demo | [docs/BILLING_DEMO.md](docs/BILLING_DEMO.md) |
| Stripe (opcional) | [docs/STRIPE_SETUP.md](docs/STRIPE_SETUP.md) |
| Correo Brevo | [docs/MAIL_BREVO_SETUP.md](docs/MAIL_BREVO_SETUP.md) |
| Google OAuth | [docs/GOOGLE_OAUTH_SETUP.md](docs/GOOGLE_OAUTH_SETUP.md) |
| Proyectos casa hogar | [docs/PROYECTOS_CASA_HOGAR.md](docs/PROYECTOS_CASA_HOGAR.md) |
| CAD / DWG | [docs/CAD_DWG.md](docs/CAD_DWG.md) |
| Entrenamiento YOLO | [docs/ENTRENAMIENTO_PLANOS.md](docs/ENTRENAMIENTO_PLANOS.md) |
| Diseño UI | [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) |
| **App móvil Flutter** | [github.com/Arcogo12/movil-Architect](https://github.com/Arcogo12/movil-Architect) |

---

## Qué no subir a Git

`.env`, `.venv`, `node_modules`, `data/` (PDF y procesados), `runs/`, `weights/`, `*.pt`, cachés npm.

---

## Solución de problemas

| Problema | Qué hacer |
|----------|-----------|
| Backend no arranca | `docker compose logs backend` — espera a que MySQL esté healthy |
| Login 401 | Verifica que corriste `init_db.py` y credenciales admin |
| Chat sin respuestas de manuales | `ingest_knowledge_docs.py` + reinicia backend |
| No detecta planos | Entrena demo o modelo real (`train_demo.py` / `train.py`) |
| Correos no llegan | Revisa `MAIL_*` y [docs/MAIL_BREVO_SETUP.md](docs/MAIL_BREVO_SETUP.md) |
| OAuth falla | `APP_BASE_URL` debe coincidir con URI autorizada en Google Console |

---

## Licencia / uso académico

Proyecto escolar. Billing en modo **demo** por defecto (sin cobros reales). Configura Stripe solo si migras a producción comercial.
