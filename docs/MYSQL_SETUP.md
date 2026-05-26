# MySQL — Plano IA

## 1. Crear base de datos

En MySQL Workbench o CLI:

```sql
CREATE DATABASE plano_ia CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

## 2. Configurar `.env`

Copia `.env.example` a `.env` y ajusta:

```
DATABASE_URL=mysql+pymysql://root:TU_PASSWORD@localhost:3306/plano_ia?charset=utf8mb4
JWT_SECRET_KEY=un-secreto-largo-unico
ADMIN_EMAIL=admin@plano-ia.local
ADMIN_PASSWORD=admin123
```

## 3. Instalar dependencias e inicializar

```powershell
cd c:\UNI\plano-validador
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts\init_db.py
```

## 4. Arrancar

```powershell
python app.py
```

- App: http://127.0.0.1:8080
- Login: http://127.0.0.1:8080/login

## Roles y planes

| Rol | Permisos |
|-----|----------|
| `user` | Chat, análisis según plan |
| `admin` | + `/api/admin/*` estadísticas y usuarios |

| Plan | Análisis/mes | Modelo real |
|------|----------------|-------------|
| free | 5 | No (solo demo) |
| starter | 30 | Sí |
| pro | 150 | Sí |
| enterprise | ilimitado | Sí |

Cada análisis se guarda en `data/uploads/{user_id}/{analysis_id}/` para historial y futuro entrenamiento.

## Stripe (próximo paso)

Campos preparados: `stripe_customer_id`, `stripe_subscription_id` en tabla `subscriptions`.
