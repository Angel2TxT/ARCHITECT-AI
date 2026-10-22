---
name: ui-ux-pro-max
description: "UI/UX design intelligence for web, mobile, and desktop. Use when designing, building, reviewing, or fixing interfaces, components, design systems, accessibility, responsive layout, typography, and styling."
---

# UI/UX Pro Max - Design Intelligence

Design intelligence and quality control for ARCHITECT interfaces across Web and Mobile.

## Core Rules for ARCHITECT

1. **Strict Monochrome (B&W) Identity**:
   - Palette is strictly Black and White (`#000000` and `#ffffff`) with alpha fills (`rgba(255,255,255,0.06)`, `rgba(0,0,0,0.04)`).
   - Zero saturated colors (no rogue greens, blues, ambers, purples, reds) unless explicitly requested for critical safety warnings.
   - Tone differences (subtle fills, solid contrast, opacity levels, dashed borders) are used instead of color hue to indicate state.

2. **Dual Theme Guarantee (Light & Dark)**:
   - Every interface must be 100% functional, legible, and tested in both Modo Claro (`html.light`) and Modo Obscuro (`html.dark`).
   - Never hardcode dark-only or light-only colors. Always bind to CSS variables (`--black`, `--white`, `--border`, `--fill-soft`, `--fill-hover`).

3. **Anti-Cluttering & Information Hierarchy**:
   - Avoid cramped inner scrolls (e.g., removing `max-height: 18rem` with scrollbars inside cards). Let sections breathe naturally.
   - Avoid duplicate summary cards (e.g., repeating client/location when already present in executive headers).
   - Structured spacing: 8px, 12px, 16px, 24px, 32px consistent rhythmic grid.

4. **Architectural Radii & Precision**:
   - Avoid bubbly, hyper-rounded capsules (pills, `rounded-3xl`, `rounded-full` on cards).
   - Use precise, architectural radii:
     - `radius-sm`: 4px (tags, badges, tiny buttons)
     - `radius-md`: 6px (buttons, inputs, table items)
     - `radius-lg`: 8px (cards, modals, panels)
     - Never use 999px pills for rectangular content containers.

5. **Data Tables & Financial Control**:
   - Right-align numeric and currency values.
   - Monospace typography for financial values (`font-mono`) to guarantee tabular figure alignment.
   - High contrast headers with subtle separating rules.
