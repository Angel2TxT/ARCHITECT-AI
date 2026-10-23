# Base de Datos ARCHITECT (MySQL 8.0+)

Este directorio contiene el script SQL completo para restaurar o inicializar la base de datos de **ARCHITECT**.

- **Archivo principal:** [`architect.sql`](architect.sql) (63 KB)
- **Motor:** MySQL 8.0+
- **Juego de caracteres:** `utf8mb4` / `utf8mb4_unicode_ci`

---

## Contenido del Dump SQL

1. **Estructura completa (23 tablas):**
   - Autenticación y roles: `users`, `plans`, `subscriptions`, `billing_receipts`, `refund_requests`, `usage_records`.
   - Workspace e IA: `chats`, `messages`, `guest_trials`, `analyses`.
   - Proyectos Casa Hogar (9 etapas): `home_projects`, `home_project_stages`, `home_project_sections`, `home_project_section_comments`, `home_project_members`, `home_project_invites`, `home_project_documents`, `home_project_events`, `home_project_ai_reviews`.
   - Soporte y notificaciones: `support_tickets`, `support_messages`, `user_notifications`, `user_device_tokens`.

2. **Datos pre-cargados:**
   - **4 Planes de suscripción:** `Gratis`, `Starter`, `Pro` y `Enterprise` (con límites, precios y características).
   - **Usuarios de prueba:**
     - Administrador: `admin@architect.local` / `admin123` (Rol Admin)
     - Usuario principal: `lopeztrujilloxd@gmail.com` / `password123` (Plan Enterprise activo)
     - Colaboradores de obra: `arq.morales@architect.local`, `ing.ruiz@architect.local`, `residente.vega@architect.local`
   - **Proyectos de ejemplo en Casa Hogar:**
     - *Residencia Bosques — Simulación Completa (100%)* (ID: `96513baa-ca57-4316-88ce-3192492bf343`):
       - 9 etapas completadas con notas técnicas y cronograma.
       - 18 apartados de entregables con presupuesto de $1.85 MDP.
       - 13 documentos registrados (planos arquitectónicos, memorias estructurales, catálogo de conceptos, bitácora y actas).
       - Colaboradores asignados y comentarios de revisión.
     - *Casa López — Ocosingo* (ID: `269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910`):
       - Proyecto activo en etapa 2 (Investigación).

---

## ¿Cómo importar la base de datos?

### Opción 1: Desde la consola de MySQL (Local sin Docker)
```powershell
# En Windows PowerShell o CMD:
mysql -u root -p < database/architect.sql

# En Linux / macOS:
mysql -u root -p < database/architect.sql
```

### Opción 2: Con Docker Desktop (Contenedor activo)
```bash
docker exec -i architect-mysql mysql -uarchitect -parchitect_pass architect < database/architect.sql
```

### Opción 3: Con gestores visuales (MySQL Workbench / DBeaver / phpMyAdmin)
1. Abre tu gestor favorito y conéctate a tu servidor MySQL.
2. Abre el archivo `database/architect.sql`.
3. Presiona el botón de **Ejecutar todo** (ícono de rayo).
4. El script creará automáticamente la base de datos `architect`, todas sus tablas e insertará los datos.
