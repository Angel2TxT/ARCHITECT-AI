# ARCHITECT Mobile App (Flutter)

Cliente Android / iOS oficial de ARCHITECT conectado a la misma API FastAPI.

Repositorio upstream: **[https://github.com/Arcogo12/movil-Architect](https://github.com/Arcogo12/movil-Architect)**

## 🚀 Cómo clonar o integrar la app aquí

Si deseas clonar el repositorio dentro de esta carpeta:
```powershell
# Desde la raíz de ARCHITECT
git clone https://github.com/Arcogo12/movil-Architect.git mobile/
cd mobile
flutter pub get
flutter run
```

## 📱 Configuración de Conexión al Backend

En la app móvil (**Ajustes → Servidor**):

| Entorno | URL del backend |
|---------|-----------------|
| Emulador Android | `http://10.0.2.2:8000` |
| Simulador iOS | `http://localhost:8000` |
| Dispositivo físico (misma Wi‑Fi) | `http://<IP_DE_TU_PC>:8000` |

Credenciales de prueba: `admin@architect.local` / `admin123`.

## 🛠️ Requisitos
- Flutter SDK ^3.11
- Backend de ARCHITECT corriendo en el puerto 8000.
