# Depth of Field Info — Design Spec

**Date:** 2026-05-13
**Status:** Approved

## Summary

Add a depth of field (DoF) display row to the FOV Overlay dialog, shown directly below the existing subject distance row. All inputs are read from EXIF; no interactive controls are added.

## Inputs

| Input | Source |
|---|---|
| Focal length (mm) | Already parsed from EXIF in dialog |
| F-number | `photo:getFormattedMetadata("aperture")` → parse "f/5.6" → 5.6 |
| Focus distance (m) | Extend `getSubjectDistance()` to return `{display, meters}` alongside existing display string |
| Crop factor | Already known in dialog (used for 35mm equivalent FL) |

**Canon range handling:** Canon bodies return FocusDistanceUpper/Lower as a range string (e.g. "3.8 m – 4.7 m"). Use the midpoint for DoF math; the display string stays as-is.

## Math

All calculations in `FOVCalculator.lua`. Internally in mm, results converted to meters.

```
-- All values in mm; distanceM is converted to mm (d = distanceM × 1000) inside the function
CoC  = 0.029 / cropFactor            -- circle of confusion (mm)
H    = fl² / (N × CoC) + fl         -- hyperfocal distance (mm)
Near = H × d / (H + d)              -- near limit (mm)
Far  = H × d / (H - d)              -- far limit (mm); nil when d ≥ H (infinity)
Span = Far - Near                    -- total DoF span (mm)
-- Results divided by 1000 before returning as meters
```

New function signature:

```lua
FOVCalculator.calculateDoF(focalLengthMM, fNumber, distanceM, cropFactor)
-- Returns: { near, far, span, hyperfocal }  (all in meters; far = nil means ∞)
```

## Display

Layout B (two rows):

```
Subject distance: 4.2 m
DoF: 3.8 m – 4.7 m  (span 0.9 m)  |  Hyperfocal: 312 m
```

When far is infinity:

```
DoF: 3.8 m – ∞  |  Hyperfocal: 312 m
```

- DoF row is hidden when subject distance or aperture is unavailable
- No new checkbox or toggle; DoF row visibility follows the existing `showDistance` condition

## Files Changed

| File | Change |
|---|---|
| `FOVCalculator.lua` | Add `calculateDoF(focalLengthMM, fNumber, distanceM, cropFactor)` |
| `FOVOverlayDialog.lua` | Parse aperture from EXIF; extend `getSubjectDistance` to return `{display, meters}`; add DoF computed property; add DoF UI row below subject distance row |

## Brand Coverage

| Brand | ExifTool tag | Format | DoF math input |
|---|---|---|---|
| Canon | `FocusDistanceUpper` + `FocusDistanceLower` | Single value or range "3.8 m – 4.7 m" | Midpoint of upper/lower |
| Nikon | `FocusDistance` | Single value | Direct |
| Sony | `FocusDistance2` | Single value | Direct |
| Olympus / OM Digital | `FocusDistance` | Single value | Direct |
| All others (Fujifilm, Panasonic, Pentax, Leica, …) | `SubjectDistance` | Single value | Direct |

Parsing: strip the " m" unit suffix from ExifTool output and convert to float. All tags return meters.

## Edge Cases

| Case | Behavior |
|---|---|
| Aperture unavailable | Hide DoF row |
| Distance unavailable | Hide DoF row (same as existing distance toggle) |
| Distance ≥ hyperfocal | Far = ∞, show "∞" |
| Canon range distance | Use midpoint of upper/lower bounds for math |
| Encoded infinity (e.g. 65535 m, 999.9 m) | Treat as ∞ — show Hyperfocal only, omit Near/Far/Span |
