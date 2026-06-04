# ARCHITECT

ARCHITECT es una plataforma para revisar planos de arquitectura, ingenieria civil e instalaciones. Combina FastAPI, React, procesamiento de imagen/CAD, reglas tecnicas configurables y modelos de deteccion para localizar inconsistencias, generar observaciones y apoyar la revision profesional antes de obra.

Documentacion util para el equipo:

- [Guia del equipo](docs/TEAM_SETUP.md)
- [Entrenamiento de planos](docs/ENTRENAMIENTO_PLANOS.md)
- [CAD, DXF y DWG](docs/CAD_DWG.md)

## Stack

- Frontend: React + Vite + Three.js + GSAP
- Backend: FastAPI + Python
- Base de datos: MySQL
- IA/vision: YOLOv8, OpenCV, reglas tecnicas configurables
- Contenedores: Docker Compose

## Arranque recomendado

Con Docker no necesitas correr `npm install` ni `pip install` manualmente. Docker instala las dependencias dentro de los contenedores:

```powershell
cd C:\UNI\ARCHITECT
docker compose up --build
```

Abre:

- Frontend React: http://localhost:3000
- Backend FastAPI: http://localhost:8000
- Docs API: http://localhost:8000/docs
- MySQL Docker: localhost:3307

React usa proxy para `/api`, `/static` y `/legacy-app`, asi el login y la app comparten el mismo origen en `localhost:3000`.

## Instalacion de dependencias

Este proyecto no usa PHP, Laravel ni Composer, asi que **no se necesita**:

```powershell
composer install
```

Para desarrollo local sin Docker, instala dependencias asi:

Backend Python:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Frontend React:

```powershell
cd frontend
npm install --cache ..\.npm-cache
```

## Flujo de analisis

```text
Plano (imagen / PDF / CAD)
      |
YOLOv8 -> elementos del plano
      |
Motor de reglas -> errores, avisos y observaciones
      |
Correcciones del usuario -> mejora del dataset y entrenamiento
```

YOLO detecta elementos del plano. Los criterios tecnicos y reglas de validacion viven en `rules/`.

## Estructura

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

## Desarrollo local sin Docker

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

## Validacion

Frontend:

```powershell
cd frontend
npm run build
```

Backend:

```powershell
.\.venv\Scripts\python.exe -m compileall -q api core db rules services scripts app.py
```

Docker:

```powershell
docker compose config
```

## Variables de entorno

Usa `.env.example` como base:

```powershell
copy .env.example .env
```

Para Docker, `docker-compose.yml` define la conexion interna de MySQL. Para desarrollo local, edita `DATABASE_URL` en `.env`.

## Notas

- La app nueva vive en `frontend/`.
- La app anterior se conserva en `web/` y se sirve en `/legacy-app`.
- No subas `.env`, `.venv`, `node_modules`, `runs`, `datasets`, `weights` ni archivos `.pt`.
- El repositorio se mantiene como `ARCHITECT-AI`.
