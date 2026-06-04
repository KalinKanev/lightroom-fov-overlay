# Portrait Photo Rotation Fix — Design Spec

**Date:** 2026-05-13
**Status:** Approved

## Summary

Fix vertical (portrait) photos displaying rotated 90° in the FOV Overlay dialog. The extracted JPEG preview is always in sensor (landscape) orientation; the renderer draws into a portrait canvas without knowing the image is sideways. The fix pre-rotates the JPEG after extraction using platform-native tools so the renderer always receives an upright image.

## Problem

`extractRawPreview()` in `FOVRenderer.lua` extracts an embedded JPEG from the RAW file via ExifTool. This JPEG is in sensor orientation (always landscape). Lightroom knows the logical orientation from EXIF, but the renderer never reads it. When the photo is portrait, the renderer draws a landscape image into a portrait-sized canvas — the subject appears rotated 90° and the FOV guide rectangle coordinates are wrong.

## Approach

Pre-rotate the JPEG file on disk immediately after extraction, before the renderer consumes it. The renderer receives an already-upright image and needs no changes.

Rotation is derived from `photo:getRawMetadata("orientation")` in `FOVOverlayDialog.lua` and passed to `FOVRenderer.renderOverlay()` as a new `rotationDeg` parameter.

## Orientation Mapping

| LR `orientation` value | Meaning | Rotation needed |
|---|---|---|
| `"AB"` | Normal (landscape) | 0° |
| `"BC"` | 90° CW (portrait) | 90° |
| `"CD"` | 180° (upside-down) | 180° |
| `"DA"` | 270° CW / 90° CCW (portrait) | 270° |
| any other / nil | Treat as normal | 0° |

All four orientations are handled.

## Platform Implementation

**macOS (`rotateJpeg` — sips branch):**
```
sips -r <degrees> <path> --out <path>
```
`sips` is a macOS built-in; no dependencies. When `degrees == 0` the call is skipped.

**Windows (`rotateJpeg` — PowerShell branch):**
```powershell
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::new('<path>')
$img.RotateFlip([System.Drawing.RotateFlipType]::Rotate<N>FlipNone)
$img.Save('<path>')
$img.Dispose()
```
`RotateFlipType` values used: `Rotate90FlipNone`, `Rotate180FlipNone`, `Rotate270FlipNone`. When `degrees == 0` the block is skipped.

## Data Flow

```
FOVOverlayDialog.lua
  photo:getRawMetadata("orientation")  →  rotationDeg (0/90/180/270)
  FOVRenderer.renderOverlay(photo, settings, rotationDeg)

FOVRenderer.lua
  extractRawPreview()  →  tempJpeg path
  rotateJpeg(tempJpeg, rotationDeg)          ← new; no-op when 0°
  renderMacOverlay(tempJpeg, ...)            ← unchanged
  renderWindowsOverlay(tempJpeg, ...)        ← unchanged
```

After rotation the JPEG dimensions match the logical orientation, so `workingWidth`/`workingHeight` (read from the image) are correct without any manual swapping.

## Files Changed

| File | Change |
|---|---|
| `FOVRenderer.lua` | Add `rotateJpeg(path, degrees)` helper; call after `extractRawPreview`; add `rotationDeg` param to `renderOverlay` |
| `FOVOverlayDialog.lua` | Read `orientation` raw metadata; map to `rotationDeg`; pass to `renderOverlay` |

## Edge Cases

| Case | Behavior |
|---|---|
| 0° / nil orientation | `rotateJpeg` is a no-op; existing behavior unchanged |
| Unknown orientation string | Map to 0° (safe default) |
| `sips` or PowerShell fails | Error propagates through existing error-handling path |
| 180° (upside-down landscape) | Rotated 180° — image stays landscape but is right-side-up |
