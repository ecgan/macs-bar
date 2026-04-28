# MacsBar App Icon Concepts

These are rough SVG directions for the app icon, based on the existing menu bar glyph in `app/Sources/MacsBar/MenuBarIconImage.swift`.

## Concepts

- `macsbar-icon-concept-a.svg` — Recommended. Cool macOS utility look. Rounded display frame with a dark bottom taskbar and four equal-width window slots. Cleanest match to the current menu bar icon.
- `macsbar-icon-concept-b.svg` — Warmer, more distinct in Finder. Same structure, but with a sand/gold palette, stronger screen outline, and equal-width window slots.
- `macsbar-icon-concept-c.svg` — More playful. Teal palette with curved background lines hinting at Spaces and motion between desktops.

## Suggested final direction

Use concept A as the base and keep these rules:

- Preserve the current menu bar metaphor: a display outline plus a thick taskbar strip.
- Make the taskbar the visual anchor, since that is the product itself.
- Keep only 4 window slots. More gets muddy at small sizes, and uneven widths do not match the app.
- Use a light macOS-style background and a dark taskbar for contrast.
- Avoid tiny text, window chrome, or multiple desktop thumbnails; they blur when shrunk to Dock size.

## If you turn this into a production icon

- Export a 1024x1024 master.
- Then generate the `.iconset` / `.icns` from that master.
- Keep padding generous so the inner display shape survives at 16px and 32px.
