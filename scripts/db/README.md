# Snapshot SQL de la base ARCHITECT

- `architect_current.sql` — esquema completo + datos clave (`plans`, `users`, `subscriptions`).
  Sin chats, mensajes, análisis ni proyectos de prueba (eran INSERT enormes).
- `dump_db.ps1` — regenera el dump crudo desde Docker.
- `trim_dump.py` — deja solo los INSERT importantes (se aplica tras el dump).
- `restore_db.ps1` — restaura el SQL (sobrescribe la BD).

```powershell
.\scripts\db\dump_db.ps1
.\.venv\Scripts\python.exe .\scripts\db\trim_dump.py
.\scripts\db\restore_db.ps1
```

Requisitos: Docker con `architect-mysql` en marcha.