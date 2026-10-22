---
name: ARCHITECT Visual Design System
colors:
  light:
    background: "#FFFFFF"
    surface: "#F8F8F9"
    surface-elevated: "#FFFFFF"
    border: "rgba(0, 0, 0, 0.10)"
    border-subtle: "rgba(0, 0, 0, 0.06)"
    text-primary: "#000000"
    text-muted: "rgba(0, 0, 0, 0.55)"
    text-subtle: "rgba(0, 0, 0, 0.35)"
    fill-soft: "rgba(0, 0, 0, 0.03)"
    fill-hover: "rgba(0, 0, 0, 0.06)"
  dark:
    background: "#000000"
    surface: "#0C0C0E"
    surface-elevated: "#141416"
    border: "rgba(255, 255, 255, 0.12)"
    border-subtle: "rgba(255, 255, 255, 0.06)"
    text-primary: "#FFFFFF"
    text-muted: "rgba(255, 255, 255, 0.60)"
    text-subtle: "rgba(255, 255, 255, 0.40)"
    fill-soft: "rgba(255, 255, 255, 0.05)"
    fill-hover: "rgba(255, 255, 255, 0.09)"
typography:
  fontFamily: "Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
  fontMono: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
  h1:
    fontSize: "1.75rem"
    fontWeight: "700"
    lineHeight: "1.2"
  h2:
    fontSize: "1.25rem"
    fontWeight: "600"
    lineHeight: "1.3"
  h3:
    fontSize: "1rem"
    fontWeight: "600"
    lineHeight: "1.4"
  body:
    fontSize: "0.875rem"
    lineHeight: "1.5"
  caption:
    fontSize: "0.75rem"
    lineHeight: "1.4"
  metric:
    fontSize: "1.5rem"
    fontWeight: "700"
    fontFamily: "fontMono"
rounded:
  none: "0px"
  sm: "4px"
  md: "6px"
  lg: "8px"
  xl: "10px"
  capsule: "9999px" # Restricted to small inline status pills only; NEVER on content containers
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
---

# ARCHITECT — Design System Specification

## Visual Philosophy: Architectural Technical Precision

ARCHITECT draws from precision blueprints, technical drafting, Swiss typographic discipline, and Apple-grade monochrome minimalism.

### Non-Negotiable Rules

1. **Strict Monochrome (B&W) Across All Screens:**
   - No color leaks. No greens, blues, ambers, or purples in UI chrome, cards, or tables.
   - States are communicated via geometric weight, opacity hierarchy, subtle tone contrast, and border styles.

2. **Full Dual-Mode Equality (Light & Dark):**
   - The interface must never look broken, washed out, or unreadable in either mode.
   - Text contrast must always surpass WCAG AA (minimum 4.5:1, targeted 7:1+).
   - In Dark Mode, backgrounds are pure deep black (`#000000`) with subtle elevated surfaces (`#0C0C0E`), and text is crisp white (`#FFFFFF`).
   - In Light Mode, backgrounds are pure white (`#FFFFFF`) with soft gray surfaces (`#F8F8F9`), and text is pure black (`#000000`).

3. **Restrained Corner Radii (No Excessive Rounding):**
   - Content cards, metric blocks, progress containers, and data tables must use technical radii (`6px` to `8px`).
   - Gigantic capsule borders (`border-radius: 9999px` or `rounded-3xl` on rectangles) are explicitly prohibited for cards. They look ungrounded and amateurish.

4. **Clutter-Free Information Architecture:**
   - Avoid nesting scrollbars within scrollbars.
   - Give metrics and financial numbers breathing room with clear label-to-value hierarchy.
   - Financial figures always render in monospace tabular digits (`fontMono`) for rapid scannability.
