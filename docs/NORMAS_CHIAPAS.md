# Normativa de construcción — Chiapas, México

Paquete integrado en **Plano Validador** (`rules/norms.py`). Referencia principal: **Reglamento de Construcción del Municipio de Tuxtla Gutiérrez, Chiapas** (P.O. 09-08/2017), aplicable como base en gran parte del estado hasta que cada ayuntamiento publique su propio reglamento.

## Marco legal (resumen)

| Nivel | Instrumento | Aplicación en el validador |
|-------|-------------|----------------------------|
| Federal | Código de Edificación de Vivienda (CONAVI) 2010 | Habitabilidad, tipología, infraestructura |
| Federal | NOM-006-CNA-1997 | Fosas sépticas (sin drenaje) |
| Federal | PROY-NOM-007-SEDATU-2024 | Habitabilidad (proyecto) |
| Estatal | Ley de Desarrollo Urbano de Chiapas | Licencias y congruencia |
| Estatal | Ley de Asentamientos Humanos, OT y DU (2018) | Ordenamiento territorial |
| Estatal | Ley de Protección Civil de Chiapas | Seguridad y evacuación |
| Municipal | Reglamento de Construcción — Tuxtla Gutiérrez | **Umbrales numéricos principales** |
| Referencia | Criterios INFONAVIT / accesibilidad IMSS | Recámaras y PCD |

## Umbrales automáticos en planta (YOLO)

Estos valores están en `CHIAPAS_RULES` y se validan si la escala (`pixels_per_meter`) es correcta:

### Puertas (Art. 150 Tuxtla)

| Parámetro | Valor | Severidad |
|-----------|-------|-----------|
| Ancho libre mínimo (acceso / calle) | **0.90 m** | Error |
| Altura de vano (referencia accesibilidad) | **2.10 m** | Aviso |

### Piezas habitables (Arts. 145-146)

| Parámetro | Valor | Severidad |
|-----------|-------|-----------|
| Dimensión mínima (lado menor en planta) | **2.70 m** | Error |
| Área mínima derivada (2.70 × 2.70) | **7.29 m²** | Error |
| Altura libre (cortes — no medido en 2D) | **2.60 m** | Documentado |
| Recámara (referencia INFONAVIT) | **9.00 m²** | Aviso |

### Ventanas e iluminación (Art. 147)

| Parámetro | Valor | Severidad |
|-----------|-------|-----------|
| Ancho mínimo | **0.60 m** | Aviso |
| Área de vanos ≥ 1/8 del piso | **12.5 %** | Aviso |
| Ventilación ≥ 1/20 del piso | **4 %** | Aviso |

### Circulación (referencia — no detectada en 2D)

| Elemento | Valor |
|----------|-------|
| Pasillos interiores | **1.20 m** |
| Escalera unifamiliar | **0.90 m** |
| Escalera plurifamiliar | **1.20 m** |
| Huella escalón | **28 cm** mín. |
| Contrahuella | **15-18 cm** |

### Accesibilidad (Arts. 234-243)

| Elemento | Valor |
|----------|-------|
| Rampas (ancho libre) | **1.20 m** |
| Pendiente rampa banqueta | **8 %** máx. |
| Cajón estacionamiento PCD | **3.80 m** |
| Sanitario accesible | **1.60 × 2.00 m** |
| Estacionamiento reservado PCD | **5 %** mínimo |

### Urbano (información)

| Concepto | Valor |
|----------|-------|
| Vivienda unifamiliar obra menor | hasta **40 m²** |
| Coeficiente de utilización (lote &lt; 300 m²) | **15 %** |
| Coeficiente de utilización (lote ≥ 300 m²) | **20 %** |
| Distancia ventana a colindante (fachada) | **1.70 m** |
| Dotación agua potable | **150 L/hab/día** |

## Ámbitos de la construcción

El validador revisa **todo el marco de construcción** en Chiapas, no solo puertas:

| Ámbito | En planta (automático) |
|--------|------------------------|
| Habitabilidad y piezas | Sí |
| Puertas y ventanas | Sí |
| Muros y cerramientos | Sí |
| Circulación interior | Sí (proxy) |
| Parámetros urbanos / superficie | Sí (estimación) |
| Accesibilidad, escaleras, estructura, instalaciones, cortes | Revisión manual / proyecto |

Tras cada análisis, la UI muestra el panel **«Ámbitos de construcción revisados»**.

## Incidencias que genera el motor

| Código | Descripción |
|--------|-------------|
| `DOOR_WIDTH_MIN` | Puerta &lt; 0.90 m |
| `DOOR_HEIGHT_MIN` | Vano bajo (accesibilidad) |
| `DOOR_OFF_WALL` | Puerta sin muro |
| `DOOR_WINDOW_OVERLAP` | Solapamiento puerta/ventana |
| `WINDOW_WIDTH_MIN` | Ventana estrecha |
| `WINDOW_AREA_MIN` | Ventana muy pequeña |
| `WINDOW_LIGHT_RATIO` | Menos de 1/8 iluminación |
| `ROOM_DIMENSION_MIN` | Pieza &lt; 2.70 m |
| `ROOM_AREA_MIN` | Superficie insuficiente |
| `ROOM_VENTILATION_OPENING` | Ventilación &lt; 1/20 |
| `BUILDING_INCOMPLETE` | Sin recintos ni muros |
| `HABITABILITY_NO_WINDOWS` | Recintos sin ventanas |
| `ROOM_NO_WINDOW` / `ROOM_NO_DOOR_ACCESS` | Recinto incompleto |
| `CORRIDOR_WIDTH_MIN` | Circulación &lt; 1.20 m |
| `BATHROOM_VENTILATION` / `KITCHEN_VENTILATION` | Sanitario / cocina |
| `BUILT_AREA_MINOR_WORK` | Superficie &gt; 40 m² (estimada) |
| `CONSTRUCTION_MANUAL_REVIEW` | Estructura, instalaciones, cortes |

## API

`GET /api/norms` — catálogo JSON para la interfaz (Configuración → Normativa aplicada).

## Municipios de Chiapas

Cada municipio puede tener reglamento propio (San Cristóbal de las Casas, Tapachula, Comitán, etc.). Si el proyecto es fuera de Tuxtla Gutiérrez, **verifica el reglamento local** y ajusta `rules/norms.py` o solicita un paquete municipal adicional.

## Calibración

Sin escala correcta (`Píxeles por metro`), las medidas en metros serán incorrectas. Usa cotas del plano o referencias conocidas (puerta estándar ~0.90 m, recámara ~3 m).

## Descargo

Esta herramienta **apoya** la revisión; no sustituye dictamen de un perito, DRO o la autoridad municipal (licencia de construcción).
