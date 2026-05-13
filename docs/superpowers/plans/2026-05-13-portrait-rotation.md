# Portrait Photo Rotation Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix vertical/portrait photos appearing rotated 90° in the FOV Overlay dialog by pre-rotating the extracted JPEG before the renderer sees it.

**Architecture:** Read `photo:getRawMetadata("orientation")` in the dialog, map it to a rotation angle (0/90/180/270°), then rotate the extracted JPEG on disk (sips on macOS, PowerShell System.Drawing on Windows) before passing it to the existing renderers. Neither `renderMacOverlay` nor `renderWindowsOverlay` changes — they receive an already-upright image.

**Tech Stack:** Lua (Lightroom Classic SDK), `sips` (macOS built-in), PowerShell `System.Drawing.Bitmap.RotateFlip` (Windows)

---

## File Map

| File | Change |
|---|---|
| `fovoverlay.lrplugin/FOVCalculator.lua` | Add `orientationToDegrees(orientationStr)` — pure mapping, testable without SDK |
| `fovoverlay.lrplugin/FOVRenderer.lua` | Add `rotateJpeg(path, degrees)` helper; update `exportUncropped` signature and body; update `createUnifiedImageView` signature to accept and forward `rotationDeg` |
| `fovoverlay.lrplugin/FOVOverlayDialog.lua` | Read `orientation` raw metadata; call `orientationToDegrees`; pass `rotationDeg` to `createUnifiedImageView` |
| `fovoverlay.lrplugin/Info.lua` | Bump version to 1.7.0 |
| `tests/test_orientation.lua` | Unit tests for `orientationToDegrees` |

---

## Task 1: Add `orientationToDegrees` to `FOVCalculator.lua` and test it

**Files:**
- Modify: `fovoverlay.lrplugin/FOVCalculator.lua`
- Create: `tests/test_orientation.lua`

- [ ] **Step 1: Write the failing test**

Create `tests/test_orientation.lua`:

```lua
-- Run from repo root: lua tests/test_orientation.lua
dofile("fovoverlay.lrplugin/FOVCalculator.lua")

local passed, failed = 0, 0
local function check(label, got, expected)
  if got == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. label .. " — got " .. tostring(got) .. ", want " .. tostring(expected))
  end
end

check("AB (normal landscape)",    FOVCalculator.orientationToDegrees("AB"),  0)
check("BC (90° CW portrait)",     FOVCalculator.orientationToDegrees("BC"),  90)
check("CD (180°)",                FOVCalculator.orientationToDegrees("CD"),  180)
check("DA (270° CW portrait)",    FOVCalculator.orientationToDegrees("DA"),  270)
check("nil → 0",                  FOVCalculator.orientationToDegrees(nil),   0)
check("unknown string → 0",       FOVCalculator.orientationToDegrees("XY"),  0)
check("empty string → 0",         FOVCalculator.orientationToDegrees(""),    0)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
```

- [ ] **Step 2: Run test to confirm it fails**

```
lua tests/test_orientation.lua
```

Expected: error like `attempt to call a nil value (field 'orientationToDegrees')`

- [ ] **Step 3: Add `orientationToDegrees` to `FOVCalculator.lua`**

Add this function just before `return FOVCalculator` at the bottom of `fovoverlay.lrplugin/FOVCalculator.lua` (currently line 215):

```lua
--[[
  Map a Lightroom orientation string to the degrees of clockwise rotation
  needed to make the image upright.
  Returns 0, 90, 180, or 270.
--]]
function FOVCalculator.orientationToDegrees(orientationStr)
  if orientationStr == "BC" then return 90
  elseif orientationStr == "CD" then return 180
  elseif orientationStr == "DA" then return 270
  else return 0 end
end
```

- [ ] **Step 4: Run test to confirm it passes**

```
lua tests/test_orientation.lua
```

Expected output:
```
7 passed, 0 failed
```

- [ ] **Step 5: Commit**

```bash
git add fovoverlay.lrplugin/FOVCalculator.lua tests/test_orientation.lua
git commit -m "feat: add orientationToDegrees mapping to FOVCalculator"
```

---

## Task 2: Add `rotateJpeg` helper to `FOVRenderer.lua`

**Files:**
- Modify: `fovoverlay.lrplugin/FOVRenderer.lua`

`rotateJpeg` modifies the JPEG at `path` in-place. It is a no-op when `degrees == 0`. On macOS it calls `sips`; on Windows it writes and executes a PowerShell script.

- [ ] **Step 1: Add `rotateJpeg` after `findExifTool` (around line 198)**

Add this function between `findExifTool` and `extractRawPreview` in `fovoverlay.lrplugin/FOVRenderer.lua`. The insertion point is after line 197 (`  return nil` / `end` of `findExifTool`) and before line 199 (`--[[`).

```lua
--[[
  Rotate the JPEG at `path` in-place by `degrees` clockwise.
  No-op when degrees is 0. macOS uses sips; Windows uses PowerShell System.Drawing.
--]]
function FOVRenderer.rotateJpeg(path, degrees)
  if not degrees or degrees == 0 then return end

  if WIN_ENV then
    local tempPath  = LrPathUtils.getStandardFilePath("temp")
    local scriptPath = LrPathUtils.child(tempPath, "fov_rotate.ps1")
    local flipType  = "Rotate" .. degrees .. "FlipNone"
    local script = table.concat({
      'Add-Type -AssemblyName System.Drawing',
      '$img = [System.Drawing.Bitmap]::new("' .. path .. '")',
      '$img.RotateFlip([System.Drawing.RotateFlipType]::' .. flipType .. ')',
      '$img.Save("' .. path .. '", [System.Drawing.Imaging.ImageFormat]::Jpeg)',
      '$img.Dispose()',
    }, "\r\n")
    local sf = io.open(scriptPath, "w+b")
    if sf then
      sf:write(script)
      sf:close()
    end
    local cmdline = 'powershell -ExecutionPolicy Bypass -File "' .. scriptPath .. '"'
    LrTasks.execute('"' .. cmdline .. '"')
    LrTasks.sleep(0.05)
    LrTasks.yield()
  else
    local singleQuoteWrap = '\'"\'"\''
    local p = path:gsub("'", singleQuoteWrap)
    LrTasks.execute(string.format(
      "sips -r %d '%s' --out '%s' 2>/dev/null", degrees, p, p))
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add fovoverlay.lrplugin/FOVRenderer.lua
git commit -m "feat: add rotateJpeg helper to FOVRenderer (sips/PowerShell)"
```

---

## Task 3: Modify `exportUncropped` to accept and apply `rotationDeg`

**Files:**
- Modify: `fovoverlay.lrplugin/FOVRenderer.lua`

`exportUncropped` currently starts at line 332. We add a `rotationDeg` parameter (defaults to 0). For JPEG originals, if rotation is needed we copy to a temp file before rotating (to avoid modifying the user's file). For RAW-extracted previews, we rotate the temp file in-place.

- [ ] **Step 1: Replace `exportUncropped` signature and JPEG branch**

Find this block (lines 332–365):

```lua
function FOVRenderer.exportUncropped(photo, displayWidth, displayHeight)
  local originalPath = photo:getRawMetadata("path")
  local ext = LrPathUtils.extension(originalPath)
  ext = ext and ext:lower() or ""

  -- JPEG files: use the original directly
  if ext == "jpg" or ext == "jpeg" then
    return { path = originalPath, isUncropped = true }
  end

  -- RAW files: try ExifTool extraction
  if FOVRenderer.rawExtensions[ext] then
    local exiftoolPath = FOVRenderer.findExifTool()
    if FOVRenderer.DEBUG_EXIFTOOL and not exiftoolPath then
      LrDialogs.message("FOV Debug", "ExifTool NOT found.\n\nPlugin path: " .. tostring(_PLUGIN.path) ..
        "\nBin path: " .. tostring(LrPathUtils.child(_PLUGIN.path, "bin")) ..
        "\nExpected: " .. (WIN_ENV and "bin\\exiftool.exe" or "bin/exiftool/exiftool"), "warning")
    end
    if exiftoolPath then
      local previewPath = FOVRenderer.extractRawPreview(exiftoolPath, originalPath)
      if previewPath then
        return { path = previewPath, isUncropped = true }
      end
    end
  else
    if FOVRenderer.DEBUG_EXIFTOOL then
      LrDialogs.message("FOV Debug", "Extension '" .. ext .. "' not in rawExtensions table.\nPath: " .. tostring(originalPath), "info")
    end
  end

  -- Fallback: use requestJpegThumbnail (returns cropped image)
  local croppedPath = FOVRenderer.exportBaseImage(photo, displayWidth, displayHeight)
  return { path = croppedPath, isUncropped = false }
end
```

Replace it with:

```lua
function FOVRenderer.exportUncropped(photo, displayWidth, displayHeight, rotationDeg)
  rotationDeg = rotationDeg or 0
  local originalPath = photo:getRawMetadata("path")
  local ext = LrPathUtils.extension(originalPath)
  ext = ext and ext:lower() or ""

  -- JPEG files: use the original directly, or a rotated temp copy when needed
  if ext == "jpg" or ext == "jpeg" then
    if rotationDeg ~= 0 then
      local tempPath = LrPathUtils.getStandardFilePath("temp")
      local tempJpeg = LrPathUtils.child(tempPath, "fov_uncropped.jpg")
      if LrFileUtils.exists(tempJpeg) then LrFileUtils.delete(tempJpeg) end
      local inf  = io.open(originalPath, "rb")
      local outf = io.open(tempJpeg, "w+b")
      if inf and outf then
        outf:write(inf:read("*a"))
        inf:close()
        outf:close()
      end
      FOVRenderer.rotateJpeg(tempJpeg, rotationDeg)
      return { path = tempJpeg, isUncropped = true }
    end
    return { path = originalPath, isUncropped = true }
  end

  -- RAW files: try ExifTool extraction
  if FOVRenderer.rawExtensions[ext] then
    local exiftoolPath = FOVRenderer.findExifTool()
    if FOVRenderer.DEBUG_EXIFTOOL and not exiftoolPath then
      LrDialogs.message("FOV Debug", "ExifTool NOT found.\n\nPlugin path: " .. tostring(_PLUGIN.path) ..
        "\nBin path: " .. tostring(LrPathUtils.child(_PLUGIN.path, "bin")) ..
        "\nExpected: " .. (WIN_ENV and "bin\\exiftool.exe" or "bin/exiftool/exiftool"), "warning")
    end
    if exiftoolPath then
      local previewPath = FOVRenderer.extractRawPreview(exiftoolPath, originalPath)
      if previewPath then
        FOVRenderer.rotateJpeg(previewPath, rotationDeg)
        return { path = previewPath, isUncropped = true }
      end
    end
  else
    if FOVRenderer.DEBUG_EXIFTOOL then
      LrDialogs.message("FOV Debug", "Extension '" .. ext .. "' not in rawExtensions table.\nPath: " .. tostring(originalPath), "info")
    end
  end

  -- Fallback: use requestJpegThumbnail (returns cropped image)
  local croppedPath = FOVRenderer.exportBaseImage(photo, displayWidth, displayHeight)
  return { path = croppedPath, isUncropped = false }
end
```

- [ ] **Step 2: Update `createUnifiedImageView` signature to accept `rotationDeg`**

Find this function signature (line 745–748):

```lua
function FOVRenderer.createUnifiedImageView(photo, allCropRects, croppedCropRects, props,
    displayWidth, displayHeight, imageWidth, imageHeight,
    croppedDisplayWidth, croppedDisplayHeight, croppedWidth, croppedHeight,
    focalLengths, cropRect, subjectDistance)
```

Replace with:

```lua
function FOVRenderer.createUnifiedImageView(photo, allCropRects, croppedCropRects, props,
    displayWidth, displayHeight, imageWidth, imageHeight,
    croppedDisplayWidth, croppedDisplayHeight, croppedWidth, croppedHeight,
    focalLengths, cropRect, subjectDistance, rotationDeg)
```

- [ ] **Step 3: Pass `rotationDeg` to `exportUncropped` inside `createUnifiedImageView`**

Find this line inside `createUnifiedImageView` (line 752):

```lua
  local uncroppedResult = FOVRenderer.exportUncropped(photo, displayWidth, displayHeight)
```

Replace with:

```lua
  local uncroppedResult = FOVRenderer.exportUncropped(photo, displayWidth, displayHeight, rotationDeg or 0)
```

- [ ] **Step 4: Commit**

```bash
git add fovoverlay.lrplugin/FOVRenderer.lua
git commit -m "feat: thread rotationDeg through exportUncropped and createUnifiedImageView"
```

---

## Task 4: Read orientation in `FOVOverlayDialog.lua` and pass to renderer

**Files:**
- Modify: `fovoverlay.lrplugin/FOVOverlayDialog.lua`

- [ ] **Step 1: Add orientation reading before the `createUnifiedImageView` call**

Find this block (lines 642–648):

```lua
    -- Build image view: unified renderer (macOS JXA / Windows PowerShell, with legacy fallback)
    local imageView = FOVRenderer.createUnifiedImageView(
      photo, allCropRects, croppedCropRects, props,
      displayWidth, displayHeight, imageWidth, imageHeight,
      croppedDisplayWidth, croppedDisplayHeight, croppedWidth, croppedHeight,
      standardFocalLengths, cropRect, subjectDistance
    )
```

Replace with:

```lua
    -- Read EXIF orientation and compute rotation needed to make image upright
    local orientationStr = photo:getRawMetadata("orientation")
    local rotationDeg = FOVCalculator.orientationToDegrees(orientationStr)

    -- Build image view: unified renderer (macOS JXA / Windows PowerShell, with legacy fallback)
    local imageView = FOVRenderer.createUnifiedImageView(
      photo, allCropRects, croppedCropRects, props,
      displayWidth, displayHeight, imageWidth, imageHeight,
      croppedDisplayWidth, croppedDisplayHeight, croppedWidth, croppedHeight,
      standardFocalLengths, cropRect, subjectDistance, rotationDeg
    )
```

- [ ] **Step 2: Commit**

```bash
git add fovoverlay.lrplugin/FOVOverlayDialog.lua
git commit -m "feat: read photo orientation and pass rotationDeg to renderer"
```

---

## Task 5: Bump version to 1.7.0

**Files:**
- Modify: `fovoverlay.lrplugin/Info.lua`

- [ ] **Step 1: Update version**

Find in `fovoverlay.lrplugin/Info.lua`:

```lua
  VERSION = { major=1, minor=6, revision=0, build=1 },
```

Replace with:

```lua
  VERSION = { major=1, minor=7, revision=0, build=1 },
```

- [ ] **Step 2: Commit**

```bash
git add fovoverlay.lrplugin/Info.lua
git commit -m "v1.7.0: Fix portrait/vertical photo orientation in FOV dialog"
```

---

## Manual Verification Checklist

After all tasks, copy the plugin to Lightroom's plugin directory and test:

1. **Portrait JPEG (90° CW):** Select a photo shot in portrait orientation (camera rotated CW). Open FOV Overlay. Image should display upright with correct FOV rectangles.
2. **Portrait JPEG (270° CW):** Select a portrait photo shot with camera rotated CCW. Same result.
3. **Portrait RAW (90° CW):** Same as above but with an ARW/CR3/NEF/ORF/RAF file. Image should be upright.
4. **Normal landscape photo:** Verify no regression — landscape photos still display correctly.
5. **Cropped landscape photo:** Verify crop overlay still renders correctly on a landscape photo with LR crop applied.
6. **180° rotated photo:** Select an upside-down photo if available. Image should be right-side-up.
