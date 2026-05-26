# Planos: imágenes, PDF, DXF y DWG

## Sin instalar programas .exe

El proyecto convierte **DWG dentro del servidor** con la librería **ezdwg** (solo `pip install`, sin ODA ni AutoCAD).

```powershell
cd c:\UNI\plano-validador
pip install "ezdwg[dxf,plot]" ezdxf matplotlib pymupdf
python app.py
```

Al arrancar deberías ver: `CAD DWG: listo via ezdwg`

Comprueba también: http://127.0.0.1:8080/api/health → `"cad": { "dwg": true, "backends": { "ezdwg": "0.9.0" } }`

## Formatos

| Formato | Cómo se procesa |
|---------|-----------------|
| PNG, JPG, WEBP | Directo |
| **PDF** | **pymupdf** → página 1 como imagen (sin .exe) |
| DXF | ezdxf + matplotlib |
| **DWG** | **ezdwg** → imagen (sin .exe) |

## PDF con varias páginas

Por defecto se analiza **la página 1**. Si el plano está en otra hoja, exporta esa página como PNG o usa un PDF de una sola página.

## Si un DWG concreto falla

- Versiones muy nuevas o archivos corruptos pueden no leerse.
- **Solución:** en AutoCAD → Guardar como → **DXF** o **PNG** y subir ese archivo.

## Herramientas externas (opcional, ya no hace falta)

Solo se usan como respaldo si ezdwg no puede leer el archivo: ODA, LibreDWG o AutoCAD+pywin32. No es necesario instalarlas para el uso normal.
