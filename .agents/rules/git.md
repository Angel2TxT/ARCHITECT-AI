# Reglas de Autonomía de Git

## Comportamiento General
Cuando el usuario te diga "sube los cambios", "haz push", "guarda en el repo" o cualquier variación:
- **NO pidas confirmación previa.**
- **NO preguntes qué mensaje de commit usar** (analiza el diff y redáctalo tú de forma concisa).
- **NO preguntes si puedes correr los comandos de Git.**
- Ejecuta toda la cadena de forma continua y autónoma:
  1. `git add .`
  2. `git commit -m "<mensaje descriptivo>"`
  3. `git push origin HEAD`
- Una vez terminado, solo responde confirmando el hash del commit y la rama a la que subiste.

---

## Casos Excepcionales: DETENERSE Y PEDIR PERMISO
ÚNICAMENTE debes pausar la ejecución y pedir permiso explícito si ocurre alguna de las siguientes situaciones:

1. **Rama principal o protegida:**
   - La rama actual es `main`, `master`, `production` o `release`. (Detén el push y pregunta).

2. **Detección de secretos o credenciales:**
   - Detectas que en el commit se incluyen archivos `.env`, tokens, claves privadas (RSA/SSH), API keys o contraseñas.

3. **Conflictos con el remoto:**
   - Al intentar hacer push, el servidor lo rechaza porque necesitas hacer `pull` o rebase y surgen conflictos de merge.

4. **Comandos destructivos o flags de fuerza:**
   - La operación requiere banderas peligrosas como `--force`, `-f`, `reset --hard` o borrado de ramas.

5. **Eliminación masiva de archivos:**
   - El cambio implica borrar carpetas completas del proyecto que no sean de build (como borrar accidentalmente `src/` o bases de datos locales).

Si NO se cumple ninguna de estas 5 condiciones, **procede de inmediato hasta completar el push.**
