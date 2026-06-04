# ARCHITECT - Guia para el equipo

Esta guia deja el proyecto listo para que cualquier integrante pueda levantar el sistema sin conocer toda la estructura interna.

## Requisitos

- Git
- Docker Desktop con Linux containers
- Windows 10/11, macOS o Linux
- 8 GB de RAM recomendados para Docker
- 30 GB libres si se van a construir dependencias de IA

Para desarrollo local sin Docker tambien se necesita:

- Python 3.10+
- Node.js 20+
- MySQL 8

## Arranque recomendado con Docker

Desde la raiz del proyecto:

```powershell
docker compose up --build
```

Servicios:

- Frontend React: http://localhost:3000
- Backend FastAPI: http://localhost:8000
- Documentacion API: http://localhost:8000/docs
- MySQL Docker: localhost:3307

El primer arranque puede tardar porque descarga MySQL, instala dependencias Python y prepara React.

## Credenciales de desarrollo

El contenedor inicializa la base y crea el usuario admin con los valores del entorno:

```text
ADMIN_EMAIL=admin@architect.local
ADMIN_PASSWORD=admin123
```

Cambia estos valores antes de usar un entorno compartido real.

## Estructura principal

```text
frontend/              React + Vite
api/                   Rutas FastAPI
core/                  Pipeline de analisis IA
services/              Servicios de autenticacion, CAD, conocimiento, almacenamiento
db/                    Modelos y conexion a base de datos
rules/                 Reglas tecnicas y catalogos
scripts/               Utilidades de entrenamiento, base de datos y Docker
web/                   App legacy servida en /legacy-app
docs/                  Documentacion del proyecto
```

## Flujo de trabajo

1. Crea una rama por cambio:

```powershell
git checkout -b feature/nombre-cambio
```

2. Levanta Docker:

```powershell
docker compose up --build
```

3. Valida frontend:

```powershell
cd frontend
npm install --cache ..\.npm-cache
npm run build
```

4. Valida backend:

```powershell
.\.venv\Scripts\python.exe -m compileall -q api core db rules services scripts app.py
```

5. Sube cambios:

```powershell
git status
git add .
git commit -m "descripcion corta"
git push
```

## Desarrollo sin Docker

Backend:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
python scripts/init_db.py
python app.py
```

Frontend:

```powershell
cd frontend
npm install --cache ..\.npm-cache
npm run dev
```

## Notas importantes

- React corre en `localhost:3000` y reenvia `/api`, `/static` y `/legacy-app` al backend.
- FastAPI corre en `localhost:8000`.
- La app vieja sigue disponible en `/legacy-app` mientras se migran pantallas a React.
- No subas `.env`, `.venv`, `node_modules`, `runs`, `datasets`, `weights` ni archivos `.pt`.
