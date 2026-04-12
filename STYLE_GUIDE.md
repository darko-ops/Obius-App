# Obius Style Guide

A quick reference for building the Obius landing page.

---

## Logo

- Primary logo files live in `/assets/`
- Use `obius transparent background.png` for light backgrounds
- Use `Obius logo clean (black back).PNG` for dark backgrounds
- The Mobius strip icon (`mobiusstrip transparent.png`) can be used as a standalone mark

---

## Colors

### Brand Palette

| Name       | Hex       | Usage                        |
|------------|-----------|------------------------------|
| Blue       | `#3B82F6` | Ideas, primary accent        |
| Yellow     | `#EAB308` | Questions, highlights        |
| Green      | `#22C55E` | Tasks, success states        |
| Purple     | `#A855F7` | Evidence, loops/portals      |
| Orange     | `#F97316` | CTAs, premium features       |

### Neutrals

| Name          | Light        | Dark         |
|---------------|--------------|--------------|
| Background    | `#FFFFFF`    | `#0A0A0A`    |
| Surface       | `#F5F5F5`    | `#171717`    |
| Border        | `#E5E5E5`    | `#262626`    |
| Text Primary  | `#0A0A0A`    | `#FAFAFA`    |
| Text Secondary| `#737373`    | `#A3A3A3`    |

### Intent Tints (for feature cards / section previews)

| Intent   | Light BG             | Dark BG              |
|----------|----------------------|----------------------|
| Idea     | `rgb(235, 242, 255)` | `rgb(26, 38, 64)`    |
| Question | `rgb(255, 250, 230)` | `rgb(51, 46, 26)`    |
| Task     | `rgb(235, 255, 242)` | `rgb(26, 51, 38)`    |
| Evidence | `rgb(245, 240, 255)` | `rgb(46, 31, 56)`    |

---

## Typography

**Font:** Inter

| Element     | Size  | Weight   |
|-------------|-------|----------|
| Hero        | 48-64px | Bold   |
| H1          | 36px  | Bold     |
| H2          | 24px  | SemiBold |
| H3          | 20px  | SemiBold |
| Body        | 16px  | Regular  |
| Small/Caption | 14px | Regular |
| Tiny        | 12px  | Medium   |

---

## Spacing

Use an **8px base grid**:

- `4px` - tight gaps (icon to label)
- `8px` - default inner padding
- `12px` - compact card padding
- `16px` - standard padding
- `24px` - section gaps
- `32px` - large section gaps
- `48-64px` - page section spacing

---

## Corners & Borders

- Buttons: `8px` radius
- Cards / containers: `12px` radius
- Small badges / tags: `6px` radius
- Inputs: `8px` radius
- Border width: `1px` (use neutral border colors above)

---

## Buttons

| Type      | Style                                          |
|-----------|-------------------------------------------------|
| Primary   | Filled orange (`#F97316`), white text, bold     |
| Secondary | Outlined, neutral border, dark text             |
| Ghost     | No border, text only, subtle hover background   |

---

## Effects

- **Glass / blur:** Use `backdrop-filter: blur(12px)` with semi-transparent backgrounds for overlays
- **Shadows:** Subtle, e.g. `0 1px 3px rgba(0,0,0,0.1)` for cards
- **Hover:** Slight scale (`1.02`) or background tint shift
- **Transitions:** `0.2s ease-in-out` for all interactive elements

---

## Dark Mode

Default to **dark mode**. Keep both modes looking clean:

- Swap background/surface/text using the neutral values above
- Intent tint colors have dark variants (see table above)
- Avoid pure white text on dark - use `#FAFAFA`
- Avoid pure black bg - use `#0A0A0A`

---

## General Rules

1. **Minimal and clean** - lots of whitespace, no clutter
2. **Let color be functional** - the 4 intent colors should feel purposeful, not decorative
3. **Dark-first** - design for dark mode first, then adapt to light
4. **Inter everywhere** - one font family, vary weight and size for hierarchy
5. **Consistent spacing** - stick to the 8px grid
