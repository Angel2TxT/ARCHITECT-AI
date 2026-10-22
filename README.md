# ARCHITECT — Inteligencia Artificial para Arquitectura & Proyectos

Plataforma integral para revisión de planos arquitectónicos con **YOLO**, asistente experto en normativas de construcción (Chiapas/Nacionales), gestión colaborativa de proyectos residenciales (**Casa Hogar**), presupuestos, peritajes y app móvil en Flutter.

- **Backend:** FastAPI (Python 3.10+) + SQLAlchemy + MySQL 8 + PyMuPDF + Ultralytics YOLO
- **Frontend Web / PWA:** HTML5 + Vanilla JS + Tailwind CSS + Service Worker offline (puerto 8000)
- **Frontend React (SPA):** React 18 + Vite + Three.js (puerto 3000)
- **App Móvil:** Flutter (Android / iOS) → [Repositorio móvil](https://github.com/Arcogo12/movil-Architect)

---

## Requisitos previos para tu laptop

Antes de comenzar, asegúrate de tener instalado en tu computadora:

| Herramienta | Versión recomendada | Obligatorio |
|-------------|---------------------|-------------|
| **Git** | 2.x o superior | Sí |
| **Python** | 3.10, 3.11, 3.12 o 3.14 | Sí (para modo local) |
| **MySQL Server** | 8.0+ (local en puerto 3306) | Sí (para modo local sin Docker) |
| **Docker Desktop** | Última versión disponible | Solo si usas Docker |
| **Node.js** | 20 LTS o superior (con npm) | Opcional (solo si desarrollas en `frontend/`) |

---

## Clonar el repositorio

Abre una terminal (PowerShell en Windows, Terminal en macOS/Linux) y clona el proyecto:

```bash
git clone https://github.com/Angel2TxT/ARCHITECT-AI.git
cd ARCHITECT-AI
```

---

## Opción A: Arranque rápido en Windows (Recomendado sin Docker)

Si vas a trabajar directamente en Windows con Python y MySQL local:

### 1. Crear las variables de entorno
Copia la plantilla de configuración tanto en la raíz como en la carpeta `backend`:

```powershell
Copy-Item .env.example .env
Copy-Item .env.example backend\.env
```

Abre `.env` y `backend\.env` y ajusta tu contraseña de MySQL:
```ini
DATABASE_URL=mysql+pymysql://root:TU_PASSWORD@localhost:3306/architect?charset=utf8mb4
```

### 2. Crear la base de datos en MySQL
Desde tu gestor de base de datos favorito (MySQL Workbench, DBeaver) o desde la consola de MySQL:

```sql
CREATE DATABASE architect CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 3. Crear entorno virtual e instalar dependencias
```powershell
# Crear entorno virtual
python -m venv .venv

# Activar entorno (si PowerShell bloquea scripts, corre antes: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass)
.\.venv\Scripts\Activate.ps1

# Instalar librerías de Python
pip install -r requirements.txt
```

### 4. Inicializar base de datos y migraciones
Ejecuta los scripts para crear las tablas, roles, usuario admin y seed de planes:

```powershell
# Inicializa tablas, planes y usuario admin inicial
python backend/scripts/init_db.py

# Aplica migraciones incrementales
python backend/scripts/migrate.py

# (Opcional) Cargar proyecto de simulación completo en Casa Hogar
python backend/scripts/populate_sample_project.py
```

### 5. Iniciar la aplicación
Simplemente ejecuta el script de arranque incluido:

```powershell
.\iniciar.ps1
```

> **¿Qué hace `.\iniciar.ps1`?**  
> Libera el puerto 8000 si estaba ocupado, verifica el entorno virtual y dependencias, y levanta el servidor FastAPI en `http://localhost:8000` con recarga automática (`--reload`).

---

## Opción B: Arranque con Docker (1 comando)

Si tienes **Docker Desktop** instalado y activo:

### 1. Variables de entorno
```powershell
Copy-Item .env.example .env
Copy-Item .env.example backend\.env
```

### 2. Construir y levantar contenedores
```bash
docker compose up --build -d
```

Esto levantará automáticamente:
- **MySQL 8:** En `localhost:3307` (usuario `architect`, clave `architect_pass`).
- **Backend FastAPI:** En `http://localhost:8000` (inicializa tablas y admin automáticamente).
- **Frontend React:** En `http://localhost:3000`.

Para detener los contenedores:
```bash
docker compose down
```

---

## URLs de Acceso

Una vez levantado el servidor en el puerto 8000:

| Módulo | URL local | Descripción |
|--------|-----------|-------------|
| **Casa Hogar (Proyectos)** | [http://localhost:8000/casa-hogar](http://localhost:8000/casa-hogar) | Gestión de obras, 9 etapas, planos, presupuesto y colaboradores. |
| **Workspace Principal** | [http://localhost:8000/legacy-app](http://localhost:8000/legacy-app) | Análisis de planos, visor, chat normativo y tickets. |
| **Landing Page** | [http://localhost:8000/](http://localhost:8000/) | Portada y bienvenida con acceso PWA. |
| **Iniciar Sesión** | [http://localhost:8000/login](http://localhost:8000/login) | Acceso de usuarios y administradores. |
| **Panel de Administración** | [http://localhost:8000/app/admin](http://localhost:8000/app/admin) | Gestión de usuarios, métricas, soporte y planes. |
| **Documentación Swagger** | [http://localhost:8000/docs](http://localhost:8000/docs) | Explorador interactivo OpenAPI / FastAPI. |

### Credenciales de prueba por defecto

```text
Usuario:  admin@architect.local
Password: admin123
```
*(Puedes cambiarlas en tu archivo `.env` mediante `ADMIN_EMAIL` y `ADMIN_PASSWORD`)*

---

## Ejecutar el Frontend React (Opcional)

El backend ya sirve la versión Web/PWA completa en el puerto 8000. Si deseas trabajar en la SPA de React:

```powershell
cd frontend
npm install
npm run dev
```
La aplicación React se abrirá en `http://localhost:3000` redirigiendo llamadas API a `http://localhost:8000`.

---

## Conexión con la App Móvil (Flutter)

El cliente móvil de ARCHITECT está disponible en:  
👉 **[https://github.com/Arcogo12/movil-Architect](https://github.com/Arcogo12/movil-Architect)**

Para conectar la app móvil con tu laptop:
1. Asegúrate de que el celular o emulador esté en la **misma red Wi-Fi** que tu laptop.
2. Averigua la IP local de tu laptop con `ipconfig` (ejemplo: `192.168.1.75`).
3. En la app móvil, ve a **Ajustes → Servidor** e ingresa:
   - **Dispositivo físico:** `http://192.168.1.75:8000`
   - **Emulador Android:** `http://10.0.2.2:8000`
   - **Simulador iOS:** `http://localhost:8000`

---

## Ejecutar Pruebas Unitarias

Para verificar que todos los módulos y reglas funcionen correctamente:

```powershell
.\.venv\Scripts\pytest
```

Todas las 53 pruebas deben pasar (`53 passed`).

---

## Estructura del Proyecto

```text
ARCHITECT-AI/
├── backend/
│   ├── api/             # Endpoints FastAPI (auth, proyectos, soporte, billing)
│   ├── core/            # Algoritmos YOLO, procesamiento geométrico y visión
│   ├── db/              # Modelos SQLAlchemy, conexión y migraciones
│   ├── rules/           # Motor de normativas de construcción (Chiapas/México)
│   ├── services/        # Lógica de negocio (Casa Hogar, PDF, email, CAD)
│   ├── scripts/         # Scripts de inicialización, demos y migraciones
│   └── tests/           # Suite de pruebas automatizadas con pytest
├── frontend/
│   ├── web/             # Interfaz web principal / PWA (HTML, JS, CSS, SW)
│   ├── src/             # Código fuente de React + Vite
│   └── public/          # Fuentes tipográficas y recursos públicos
├── data/                # Almacenamiento local (avatares, documentos raw)
├── iniciar.ps1          # Script de arranque rápido en 1 clic para Windows
├── docker-compose.yml   # Orquestación de contenedores Docker
├── requirements.txt     # Dependencias de Python
└── README.md            # Documentación del proyecto
```

---

## Solución de Problemas Frecuentes

1. **PowerShell bloquea la activación del entorno virtual (`Activate.ps1`):**
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

2. **Error al conectar a MySQL (`Access denied` o `Can't connect`):**
   - Asegúrate de que el servicio de MySQL esté iniciado (`services.msc` en Windows).
   - Verifica que el usuario y la contraseña en `.env` coincidan con los de tu MySQL local.

3. **No veo reflejados los cambios recientes en la web (lápiz de edición, botones, etc.):**
   - El Service Worker de la PWA guarda archivos en caché. Realiza una **recarga forzada**:
     > Presiona **`Ctrl + F5`** (o `Ctrl + Shift + R`).

4. **Puerto 8000 ocupado:**
   - Al ejecutar `.\iniciar.ps1`, el script detecta y libera automáticamente cualquier proceso previo colgado en el puerto 8000.
