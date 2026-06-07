# ARCHITECT Design System

Base visual aplicada desde `Digital Experiences | Premium Studio`.

## Principios

- Dark mode como base.
- Composicion full bleed con grid visible.
- Superficies glass con borde sutil y blur.
- Acentos principales violet/blue.
- Movimiento expresivo, controlado y orientado a interfaz.

## Tokens

```text
primary:   #8B5CF6
secondary: #3B82F6
tertiary:  #A78BFA
neutral:   #0B0B0D
surface:   rgba(255, 255, 255, 0.035)
text:      #FFFFFF
muted:     #94A3B8
border:    rgba(255, 255, 255, 0.1)
```

## Tipografia

- Familia: Inter.
- Display: grande, peso 700, responsive con `clamp()` para no romper mobile.
- Body: 16px, peso 300-400, line-height cercano a 24px.
- Labels: uppercase, 12px, peso 600-800, letter spacing amplio.

## Layout

- Base rhythm: 4px.
- Gaps: 2px, 8px, 12px, 14px, 16px, 20px, 24px.
- Section padding: 24px, 28px, 32px, 40px.
- Radios: 16px, 24px, 28px, 32px, 40px, 9999px.

## Superficies

Usar glass surfaces:

```css
background: rgba(255, 255, 255, 0.035);
border: 1px solid rgba(255, 255, 255, 0.1);
backdrop-filter: blur(24px);
box-shadow: 0 1px 0 rgba(255, 255, 255, 0.06) inset;
```

Para shells premium:

```css
background:
  linear-gradient(rgba(11, 11, 13, 0.82), rgba(11, 11, 13, 0.82)) padding-box,
  linear-gradient(145deg, rgba(168, 85, 247, 0.35), rgba(255, 255, 255, 0.08) 42%, transparent) border-box;
```

## Motion

- Duraciones principales: 300ms, 500ms, 550ms, 700ms, 800ms.
- Easing preferido: `cubic-bezier(0.16, 1, 0.3, 1)` para entradas y `ease` para cambios simples.
- Hover: color, border, glow, shadow y desplazamientos sutiles.

## WebGL / 3D

- Three.js con renderer `alpha`, `antialias` y DPR clamp.
- Escenas como acento inset 3D.
- Fondo tecnico con perspective grid o grid de profundidad.
- Motion: slow orbital drift, breathing pulse y pointer drift sutil cuando aplique.

## Aplicacion en el proyecto

- `frontend/src/styles.css`: sistema principal React para welcome, login y shell.
- `web/static/style.css`: overrides para la app legacy servida en `/legacy-app`.
- `frontend/src/main.jsx`: mantiene Three.js/GLB loader para el 3D del inicio.
