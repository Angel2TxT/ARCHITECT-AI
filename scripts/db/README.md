# Snapshot SQL de la base ARCHITECT

- `architect_current.sql` — dump completo (esquema + datos) del contenedor `architect-mysql`.
- `dump_db.ps1` — regenera el dump.
- `restore_db.ps1` — restaura el dump (sobrescribe la BD).

Requisitos: Docker con `architect-mysql` en marcha (`docker compose up -d mysql`).
