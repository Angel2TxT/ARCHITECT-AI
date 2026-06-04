# Mantenimiento del repositorio

## Nombre recomendado

El repositorio debe llamarse:

```text
architect
```

Si tienes GitHub CLI instalado y autenticado:

```powershell
gh repo edit Angel2TxT/ARCHITECT-AI --name architect
git remote set-url origin https://github.com/Angel2TxT/architect.git
```

Si no tienes `gh`, renombralo desde GitHub:

1. Abre el repositorio en GitHub.
2. Entra a `Settings`.
3. Cambia `Repository name` a `architect`.
4. Ejecuta localmente:

```powershell
git remote set-url origin https://github.com/Angel2TxT/architect.git
```

GitHub normalmente redirige la URL anterior, pero es mejor actualizar el remoto local.

## Comandos utiles

Ver remoto actual:

```powershell
git remote -v
```

Ver rama actual:

```powershell
git branch --show-current
```

Subir cambios:

```powershell
git add .
git commit -m "mensaje"
git push
```
