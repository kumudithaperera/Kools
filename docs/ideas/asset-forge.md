# Asset Forge (idea, not built)

Brief from the "Drop-Folder Icon and Asset Pipeline" T3 thread (2026-11-18). It stopped
at Gate A; no code was written. If it's built, it becomes a Kools module (a tab plus a
Core target) instead of a separate app.

**Tested first:** macOS can turn an SVG into a 1024×1024 transparent PNG with nothing
installed. A test circle in `#E8552D` came out with exactly that color on a transparent
background, so the tool needs no ImageMagick, rsvg or Inkscape.

## Goal

Drop an SVG into a folder and get every Expo and store asset back, centered, with its
colors checked against the design tokens.

## Shape

Watches `~/AssetForge/Drop/`. For each SVG dropped there, it writes the results to
`~/AssetForge/Out/<name>/` and sends a notification.

## Outputs per SVG

| File | Size | Notes |
|---|---|---|
| `icon.png` | 1024² | Solid background, because iOS rejects icons with transparency |
| `adaptive-icon.png` | 1024² | Transparent, artwork kept inside Android's center 66% safe zone |
| `monochrome-icon.png` | 1024² | One color on transparent |
| `splash-icon.png` | 1024² | Transparent, for `expo-splash-screen` |
| `notification-icon.png` | 96² | White on transparent, which Android requires |
| `favicon.png` | 48² | |
| `transparent/` | 1024, plus 256 @1x/2x/3x | Reusable transparent images |
| `app.json.snippet` | | The matching config lines to paste |

**Auto-centering:** trim the artwork to its visible edges, then center it with a set
amount of padding.

**Color check:** read every fill, stroke and gradient color in the SVG and find the
closest token in Morsel's `constants/theme.ts` (paprika, basil, honey, the neutral and
charcoal shades). Colors not close to a token are flagged in a `report.md` next to the
outputs.

**Safety:** never writes into the Morsel repo. Copying files into `app/assets/images`
stays a manual step.

## Steps

1. Core: render the SVG, trim and center, export each size.
2. Core: read the tokens and check the colors.
3. UI: Kools tab, folder watcher, notifications, "Open output".
4. Tests for the centering math, the token reader and the color matching. Then run it
   on the Morsel Plus SVG.

Simplicity level (Ponytail): lite. No dependencies.

## Open decisions

1. **Play Store screenshot framing:** leave it out of v1 and add it later (recommended),
   or include it now?
2. **Token source:** read Morsel's `theme.ts` directly so it stays in sync (recommended),
   or keep a separate `tokens.json` so other projects can use it?
3. **Folder location:** `~/AssetForge/Drop` and `~/AssetForge/Out` (recommended), or
   somewhere inside this repo?
4. **Background colors:** `#FFFFFF` for the adaptive icon and `#FAD9B1` for the splash,
   as in the current `app.json`, or paprika for the icon background?
