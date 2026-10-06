# Crop-Equivalent ISO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an approximate "crop-equivalent ISO" for the current Lightroom crop and for every FOV guide rectangle, drawn as labels on the overlay image, in the focal-length legend, and in the header.

**Architecture:** Pure math (`parseISO`, `roundToThirdStopISO`, `equivalentISO`, `formatISOValue`, `selectLabeledFLs`) goes in `FOVCalculator.lua` and is unit-tested with plain Lua. `FOVOverlayDialog.lua` reads the shot ISO, annotates each crop rect with an `isoLabel`, extends the header and legend, and adds a "Show ISO equiv" toggle. `FOVRenderer.lua` draws a small dark label at the top-left corner of each labeled rectangle in both the macOS (JXA/Cocoa) and Windows (PowerShell/System.Drawing) renderers.

**Tech Stack:** Lua 5.x (Lightroom SDK), JXA + Cocoa (macOS), PowerShell + System.Drawing (Windows), `/opt/homebrew/bin/lua` for unit tests.

---

## Background: the method

Steve Perry (Backcountry Gallery) argues that cropping does not change per-pixel noise, but it does change the noise you see at a fixed output size. Fewer pixels must be enlarged more, so the noise is enlarged with them. His practical advice is to drop ISO when a heavy crop is expected. Sources:

- https://backcountrygallery.com/the-cropping-epidemic/ ("the fewer pixels you have, the larger those pixels must be for any given output")
- https://backcountrygallery.com/cropping-better-drop-your-iso/ (trades 1/3200 @ ISO 6400 for 1/1600 @ ISO 3200 when a crop is expected)
- https://backcountrygallery.com/does-cropping-make-your-photos-noisy/ and the video https://www.youtube.com/watch?v=h4iQmjONCb8
- BCG Forums threads quote the rule as "crop factor squared times ISO" (forum pages are behind a 403 for automated fetches; the rule is the standard equivalence result).

The quantitative rule, valid when photon shot noise dominates and output size is held constant:

```
areaRatio      = fullSensorArea / cropArea          (pixels or mm², same thing)
equivalentISO  = shotISO × areaRatio
stops (EV)     = log2(areaRatio)
```

For crops that keep the sensor's aspect ratio, `areaRatio = (linear crop factor)²`, so a 2× crop is ×4 ISO (+2 EV) and a 1.5× (DX-style) crop is ×2.25 ISO (+1.2 EV). For FOV guides, the linear factor is `targetFL / shotFL`.

**Design decisions (locked for this plan):**

1. **Reference frame is the camera's own full sensor.** The number answers "what ISO would an uncropped frame from this same camera need to look this noisy at the same print size?" It does not convert APS-C/MFT to full-frame equivalence. See Open Questions.
2. **Area-based, not FL-based.** Using `rect.width × rect.height` against `imageWidth × imageHeight` handles non-native aspect-ratio crops and the cropped view correctly, and gives one code path for both views.
3. **Display rounds to the nearest standard 1/3-stop ISO** and always carries the `≈` sign, plus the EV delta with one decimal. Example label: `500mm  ≈ISO 6400 (+2.0 EV)`.
4. **Missing ISO falls back to EV only.** Example: `500mm  +2.0 EV`.
5. **Labels that would overlap a previous label are skipped**; the legend next to each checkbox always shows the value, so nothing is lost.
6. The legacy corner-PNG renderer gets no labels; the legend covers it.

## File map

| File | Change |
|---|---|
| `fovoverlay.lrplugin/FOVCalculator.lua` | Add ISO math and label layout helpers |
| `tests/test_iso.lua` | New unit tests |
| `fovoverlay.lrplugin/FOVOverlayDialog.lua` | Read ISO, annotate rects, header suffix, legend column, toggle, tooltip |
| `fovoverlay.lrplugin/FOVRenderer.lua` | Draw labels (macOS + Windows), new `showLabels` param, re-render on toggle |
| `fovoverlay.lrplugin/FOVInfoProvider.lua` | Mention the ISO formula in About |
| `README.md` | Document the feature and its caveats |

---

### Task 1: ISO math in `FOVCalculator`

**Files:**
- Create: `tests/test_iso.lua`
- Modify: `fovoverlay.lrplugin/FOVCalculator.lua` (insert before the final `return FOVCalculator`, currently line 227)

- [ ] **Step 1: Write the failing test**

Create `tests/test_iso.lua`:

```lua
-- tests/test_iso.lua
-- Run from repo root: lua tests/test_iso.lua

local FOVCalculator = dofile("fovoverlay.lrplugin/FOVCalculator.lua")

local pass, fail = 0, 0
local function check(desc, got, expected, tolerance)
  tolerance = tolerance or 0.001
  local ok = (got == expected) or (type(got) == "number" and type(expected) == "number" and math.abs(got - expected) < tolerance)
  if ok then
    pass = pass + 1
    print("  PASS  " .. desc)
  else
    fail = fail + 1
    print("  FAIL  " .. desc .. "  got=" .. tostring(got) .. "  expected=" .. tostring(expected))
  end
end

-- parseISO
check("parseISO number",        FOVCalculator.parseISO(3200),        3200)
check("parseISO 'ISO 3200'",    FOVCalculator.parseISO("ISO 3200"),  3200)
check("parseISO '12,800'",      FOVCalculator.parseISO("12,800"),    12800)
check("parseISO nil",           FOVCalculator.parseISO(nil),         nil)
check("parseISO zero",          FOVCalculator.parseISO(0),           nil)
check("parseISO garbage",       FOVCalculator.parseISO("abc"),       nil)

-- roundToThirdStopISO
check("round 6400 exact",       FOVCalculator.roundToThirdStopISO(6400),   6400)
check("round 7000 -> 6400",     FOVCalculator.roundToThirdStopISO(7000),   6400)
check("round 900 -> 1000",      FOVCalculator.roundToThirdStopISO(900),    1000)
check("round beyond table",     FOVCalculator.roundToThirdStopISO(500000), 500000)
check("round nil",              FOVCalculator.roundToThirdStopISO(nil),    nil)

-- equivalentISO: 2x linear crop = 4x area = +2 EV
local e1 = FOVCalculator.equivalentISO(800, 4000000, 1000000)
check("e1 ratio",   e1.ratio,   4)
check("e1 stops",   e1.stops,   2)
check("e1 iso",     e1.iso,     3200)
check("e1 display", e1.display, 3200)

-- 1.5x linear crop (DX-style) = 2.25x area = +1.17 EV, ISO 400 -> 900 -> shown as 1000
local e2 = FOVCalculator.equivalentISO(400, 2.25, 1)
check("e2 stops",   e2.stops,   1.1699, 0.001)
check("e2 iso",     e2.iso,     900)
check("e2 display", e2.display, 1000)

-- No ISO in metadata: stops still computed
local e3 = FOVCalculator.equivalentISO(nil, 4, 1)
check("e3 stops",   e3.stops,   2)
check("e3 iso nil", e3.iso,     nil)

-- Invalid areas
check("invalid area nil", FOVCalculator.equivalentISO(800, 0, 1), nil)
check("invalid crop nil", FOVCalculator.equivalentISO(800, 1, nil), nil)

-- formatISOValue
check("fmt full",     FOVCalculator.formatISOValue(e1, "~", true),  "~ISO 3200 (+2.0 EV)")
check("fmt short",    FOVCalculator.formatISOValue(e1, "~", false), "~ISO 3200")
check("fmt no iso",   FOVCalculator.formatISOValue(e3, "~", true),  "+2.0 EV")
check("fmt no iso s", FOVCalculator.formatISOValue(e3, "~", false), "+2.0 EV")
check("fmt nil",      FOVCalculator.formatISOValue(nil, "~", true), "")

-- selectLabeledFLs: rects sorted outermost first; 300 is too close to 200
local rects = {
  { focalLength = 200, top = 100 },
  { focalLength = 300, top = 110 },
  { focalLength = 400, top = 200 },
}
local s1 = FOVCalculator.selectLabeledFLs(rects, { 200, 300, 400 }, 1.0, 30)
check("s1 200 labeled",   s1[200], true)
check("s1 300 skipped",   s1[300], nil)
check("s1 400 labeled",   s1[400], true)
local s2 = FOVCalculator.selectLabeledFLs(rects, { 300, 400 }, 1.0, 30)
check("s2 300 labeled (200 hidden)", s2[300], true)
check("s2 400 labeled",   s2[400], true)
local s3 = FOVCalculator.selectLabeledFLs(rects, { 200, 300, 400 }, 0.1, 30)
check("s3 scaled: only 200", s3[200] == true and s3[300] == nil and s3[400] == nil, true)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_iso.lua`
Expected: error `attempt to call a nil value (field 'parseISO')`.

- [ ] **Step 3: Implement the helpers**

Insert into `fovoverlay.lrplugin/FOVCalculator.lua` immediately before `return FOVCalculator`:

```lua
--[[
  Crop-equivalent ISO (after Steve Perry's crop-vs-ISO guidance).

  At a fixed output size, cropping to a fraction of the sensor area
  enlarges the noise the same way raising ISO by the inverse fraction does
  (photon shot noise dominated). So:

    areaRatio     = fullArea / cropArea
    equivalentISO = shotISO * areaRatio
    stops         = log2(areaRatio)

  Approximate: ignores read noise, sensor differences and denoise.
--]]

-- Standard 1/3-stop ISO series used for display rounding
local THIRD_STOP_ISOS = {
  50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250,
  1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000,
  25600, 32000, 40000, 51200, 64000, 80000, 102400, 128000, 160000, 204800,
  256000, 320000, 409600,
}

--[[
  Parse ISO from Lightroom metadata.
  Accepts a number (getRawMetadata) or a string like "ISO 3200" / "12,800".
  Returns a positive number or nil.
--]]
function FOVCalculator.parseISO(value)
  if type(value) == "number" then
    return value > 0 and value or nil
  end
  if type(value) ~= "string" then return nil end
  local n = tonumber((value:gsub("[^%d]", "")))
  if n and n > 0 then return n end
  return nil
end

--[[
  Round an ISO value to the nearest standard 1/3-stop ISO (log distance).
  Values well beyond the table are rounded to the nearest 1000.
--]]
function FOVCalculator.roundToThirdStopISO(iso)
  if not iso or iso <= 0 then return nil end
  if iso > THIRD_STOP_ISOS[#THIRD_STOP_ISOS] * 1.12 then
    return math.floor(iso / 1000 + 0.5) * 1000
  end
  local best, bestDiff = nil, math.huge
  for _, v in ipairs(THIRD_STOP_ISOS) do
    local d = math.abs(math.log(iso / v))
    if d < bestDiff then
      best, bestDiff = v, d
    end
  end
  return best
end

--[[
  Compute the crop-equivalent ISO.

  Parameters:
    baseISO:  Shot ISO (number) or nil when unknown
    fullArea: Full sensor area in pixels (imageWidth * imageHeight)
    cropArea: Crop area in the same pixel units

  Returns table { ratio, stops, iso, display } or nil for invalid areas.
  iso and display are nil when baseISO is nil.
--]]
function FOVCalculator.equivalentISO(baseISO, fullArea, cropArea)
  if not fullArea or not cropArea or fullArea <= 0 or cropArea <= 0 then return nil end
  local ratio = fullArea / cropArea
  local stops = math.log(ratio) / math.log(2)
  local iso, display
  if baseISO then
    iso = baseISO * ratio
    display = FOVCalculator.roundToThirdStopISO(iso)
  end
  return { ratio = ratio, stops = stops, iso = iso, display = display }
end

--[[
  Format an equivalentISO result for display.
    approx:    the "approximately" glyph to use (UTF-8 for LrView, an escape for scripts)
    includeEV: append "(+x.x EV)" when the ISO is known
  Examples: "≈ISO 3200 (+2.0 EV)", "≈ISO 3200", "+2.0 EV"
--]]
function FOVCalculator.formatISOValue(eq, approx, includeEV)
  if not eq then return "" end
  local ev = string.format("+%.1f EV", eq.stops)
  if not eq.display then return ev end
  local isoStr = string.format("%sISO %d", approx, eq.display)
  if includeEV then
    return isoStr .. " (" .. ev .. ")"
  end
  return isoStr
end

--[[
  Choose which enabled rects get an on-image label so labels don't collide.
  Rects must be sorted outermost first (ascending focal length), which is
  how calculateAllCropRects returns them. Labels sit at each rect's top-left
  corner, so a rect is labeled only if its top edge is at least labelHeight
  display pixels below the previous labeled rect's top edge.

  Parameters:
    rects:       crop rect tables with focalLength and top (working pixels)
    enabledFLs:  array of checked focal lengths
    scaleY:      display pixels per working pixel
    labelHeight: label box height in display pixels

  Returns a set { [focalLength] = true }.
--]]
function FOVCalculator.selectLabeledFLs(rects, enabledFLs, scaleY, labelHeight)
  local enabled = {}
  for _, fl in ipairs(enabledFLs) do enabled[fl] = true end
  local result, lastTop = {}, nil
  for _, rect in ipairs(rects) do
    if enabled[rect.focalLength] then
      local top = rect.top * scaleY
      if lastTop == nil or (top - lastTop) >= labelHeight then
        result[rect.focalLength] = true
        lastTop = top
      end
    end
  end
  return result
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/test_iso.lua && lua tests/test_dof.lua && lua tests/test_orientation.lua`
Expected: `test_iso.lua` ends with `33 passed, 0 failed`; the other two suites still pass.

- [ ] **Step 5: Commit**

```bash
git add tests/test_iso.lua fovoverlay.lrplugin/FOVCalculator.lua
git commit -m "feat: add crop-equivalent ISO math helpers"
```

---

### Task 2: Read ISO and annotate crop rects in the dialog

**Files:**
- Modify: `fovoverlay.lrplugin/FOVOverlayDialog.lua` (after the DoF block ending line 306; after the color-index loop ending line 543)

- [ ] **Step 1: Read the shot ISO and compute the current crop's equivalent**

Insert right after the DoF block (after `dofResult = FOVCalculator.calculateDoF(...)` / `end`, line 306):

```lua
    -- Shot ISO and crop-equivalent ISO for the current Lightroom crop
    local baseISO = FOVCalculator.parseISO(photo:getRawMetadata("isoSpeedRating"))
      or FOVCalculator.parseISO(photo:getFormattedMetadata("isoSpeedRating"))
    local fullArea = imageWidth * imageHeight
    local currentCropEq = isCropped
      and FOVCalculator.equivalentISO(baseISO, fullArea, croppedWidth * croppedHeight)
      or nil
```

- [ ] **Step 2: Annotate each FOV rect with its equivalent ISO and label text**

Insert right after the loop that assigns `rect.colorIndex` for `croppedCropRects` (ends line 543):

```lua
    -- Crop-equivalent ISO per FOV rect, always relative to the full sensor.
    -- Rect width/height are in sensor pixels in both views, so one formula works.
    -- "{approx}" is replaced per renderer (UTF-8 can't be written safely into the scripts).
    local function annotateISO(rects)
      for _, rect in ipairs(rects) do
        rect.isoEq = FOVCalculator.equivalentISO(baseISO, fullArea, rect.width * rect.height)
        rect.isoLabel = string.format("%dmm  %s", rect.focalLength,
          FOVCalculator.formatISOValue(rect.isoEq, "{approx}", true))
      end
    end
    annotateISO(allCropRects)
    if croppedCropRects ~= allCropRects then
      annotateISO(croppedCropRects)
    end
```

- [ ] **Step 3: Syntax check**

Run: `luac -p fovoverlay.lrplugin/FOVOverlayDialog.lua`
Expected: no output (exit 0). If `luac` is missing, use `lua -e 'assert(loadfile("fovoverlay.lrplugin/FOVOverlayDialog.lua"))'`.

- [ ] **Step 4: Commit**

```bash
git add fovoverlay.lrplugin/FOVOverlayDialog.lua
git commit -m "feat: compute crop-equivalent ISO for current crop and FOV rects"
```

---

### Task 3: Toggle, header suffix, legend column, tooltip

**Files:**
- Modify: `fovoverlay.lrplugin/FOVOverlayDialog.lua`

- [ ] **Step 1: Add the toggle property**

Next to `props.showDistance = (subjectDistance ~= nil)` (line 312), add:

```lua
    -- Whether to show crop-equivalent ISO in header, legend and overlay labels
    props.showISO = true
```

- [ ] **Step 2: Add an ISO suffix for the header**

Below the `withDist` function (line 326), add:

```lua
    -- Append shot ISO, or crop-equivalent ISO when the photo is cropped
    local function withISO(s)
      if not props.showISO then return s end
      if currentCropEq then
        return s .. "  |  " .. FOVCalculator.formatISOValue(currentCropEq, "\226\137\136", true) .. " equiv"
      elseif baseISO then
        return s .. string.format("  |  ISO %d", baseISO)
      end
      return s
    end
```

Then wrap the three header `return withDist(string.format(...))` calls in `buildFullFrameHeader` and `buildCroppedHeader` as `return withDist(withISO(string.format(...)))`. Concretely, the three lines become:

```lua
        return withDist(withISO(string.format("%s  |  Cropped to %dmm equiv  |  %d \195\151 %d  |  %.1f MP",
          flLabel, effectiveFL, croppedWidth, croppedHeight, (croppedWidth * croppedHeight) / 1000000)))
```
```lua
        return withDist(withISO(string.format("%s  |  %d \195\151 %d  |  %.1f MP",
          flLabel, imageWidth, imageHeight, (imageWidth * imageHeight) / 1000000)))
```
```lua
      return withDist(withISO(string.format("%s  |  Cropped to %dmm equiv  |  %d \195\151 %d  |  %.1f MP",
        flLabel, effectiveFL, croppedWidth, croppedHeight, (croppedWidth * croppedHeight) / 1000000)))
```

- [ ] **Step 3: Legend values per focal length**

After `annotateISO(...)` from Task 2, add:

```lua
    -- Legend text per FL for the active view ("" when the FL has no rect in this view)
    local function updateLegendISO()
      local rects = (props.viewMode == "cropped") and croppedCropRects or allCropRects
      local byFL = {}
      for _, rect in ipairs(rects) do byFL[rect.focalLength] = rect end
      for _, fl in ipairs(standardFocalLengths) do
        local rect = byFL[fl]
        props["iso_" .. fl] = (props.showISO and rect)
          and FOVCalculator.formatISOValue(rect.isoEq, "\226\137\136", false)
          or ""
      end
    end
    updateLegendISO()
    props:addObserver("viewMode", function() updateLegendISO() end)
```

- [ ] **Step 4: Rebuild header and legend when the toggle changes**

Immediately after the `props:addObserver("viewMode", function() updateLegendISO() end)` line from Step 3, add the observer below. It must come after `updateLegendISO` is defined, because a Lua closure can only see locals declared above it. Do not put it next to the `showDistance` observer, which sits earlier in the file.

```lua
    props:addObserver("showISO", function()
      if props.viewMode == "cropped" then
        props.headerText = buildCroppedHeader()
      else
        props.headerText = buildFullFrameHeader()
      end
      updateLegendISO()
    end)
```

- [ ] **Step 5: Show the value in each checkbox row**

In the checkbox row builder (`table.insert(columns[colIndex], f:row { ... })`, line 615), add a third child after the colored-square `f:static_text`:

```lua
        f:static_text {
          title = LrView.bind("iso_" .. fl),
          font = "<system/small>",
          text_color = LrColor(0.65, 0.65, 0.65),
          width_in_chars = 9,
          visible = isAvailable and LrView.bind("show_" .. fl) or false,
        },
```

- [ ] **Step 6: Add the checkbox with an explanatory tooltip**

In the controls row, after the `Show distance` checkbox (line 701-705), add:

```lua
      f:checkbox {
        title = "Show ISO equiv",
        value = LrView.bind("showISO"),
        tooltip = "Approximate noise-equivalent ISO at the same output size:\n" ..
                  "ISO \195\151 (full frame area \195\183 crop area).\n" ..
                  "Based on Steve Perry's crop-vs-ISO guidance. Ignores read noise and denoise.",
      },
```

- [ ] **Step 7: Syntax check**

Run: `luac -p fovoverlay.lrplugin/FOVOverlayDialog.lua`
Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add fovoverlay.lrplugin/FOVOverlayDialog.lua
git commit -m "feat: show crop-equivalent ISO in header and legend with toggle"
```

---

### Task 4: Draw ISO labels on the macOS overlay

**Files:**
- Modify: `fovoverlay.lrplugin/FOVRenderer.lua` (imports near line 15; `renderMacOverlay` at line 443)

- [ ] **Step 1: Import the calculator**

Below `local LrDialogs = import 'LrDialogs'` (line 15), add:

```lua
local FOVCalculator = require 'FOVCalculator'
```

- [ ] **Step 2: Add the `showLabels` parameter**

Change the signature at line 443 to:

```lua
function FOVRenderer.renderMacOverlay(baseImagePath, allCropRects, enabledFLs, displayWidth, displayHeight, workingWidth, workingHeight, renderCount, highlightFL, cropRect, showLabels)
```

- [ ] **Step 3: Emit label drawing after the highlight dimming**

Insert immediately before `table.insert(lines, "img.unlockFocus")` (line 592), so labels stay readable on top of the dimming:

```lua
  -- Crop-equivalent ISO labels at each rect's top-left corner
  if showLabels then
    local labelFont = math.max(11, math.floor(displayWidth / 75))
    local labelHeight = math.floor(labelFont * 1.4) + 4
    local labeled = FOVCalculator.selectLabeledFLs(
      allCropRects, enabledFLs, displayHeight / workingHeight, labelHeight)

    table.insert(lines, string.format("var lblFont = $.NSFont.boldSystemFontOfSize(%d)", labelFont))
    table.insert(lines, "var lblBg = $.NSColor.colorWithCalibratedRedGreenBlueAlpha(0, 0, 0, 0.6)")
    table.insert(lines, "function drawLabel(text, x, yTop, r, g, b) {")
    table.insert(lines, "  var attrs = $.NSMutableDictionary.dictionary")
    table.insert(lines, "  attrs.setObjectForKey(lblFont, $.NSFontAttributeName)")
    table.insert(lines, "  attrs.setObjectForKey($.NSColor.colorWithCalibratedRedGreenBlueAlpha(r, g, b, 1), $.NSForegroundColorAttributeName)")
    table.insert(lines, "  var s = $.NSString.stringWithString(text)")
    table.insert(lines, "  var sz = s.sizeWithAttributes(attrs)")
    table.insert(lines, "  var bx = x + pw + 2")
    table.insert(lines, "  var by = yTop - pw - 2 - sz.height - 4")
    table.insert(lines, "  lblBg.set")
    table.insert(lines, "  $.NSBezierPath.fillRect($.NSMakeRect(bx, by, sz.width + 8, sz.height + 4))")
    table.insert(lines, "  s.drawAtPointWithAttributes($.NSMakePoint(bx + 4, by + 2), attrs)")
    table.insert(lines, "}")

    for i, rect in ipairs(allCropRects) do
      if labeled[rect.focalLength] and rect.isoLabel then
        local colorIndex = rect.colorIndex or (((i - 1) % #FOVRenderer.colorNames) + 1)
        local rgb = FOVRenderer.colorRGB[FOVRenderer.colorNames[colorIndex]]
        -- JS string literal: U+2248 via escape; label text is otherwise ASCII
        local text = rect.isoLabel:gsub("{approx}", "\\u2248"):gsub("'", "\\'")
        if rect.rotatedCorners then
          local ul = rect.rotatedCorners[1]
          table.insert(lines, string.format(
            "drawLabel('%s', Math.floor(%s * imgW), imgH - Math.floor(%s * imgH), %s, %s, %s)",
            text, ul[1], ul[2], rgb[1] / 255, rgb[2] / 255, rgb[3] / 255))
        else
          table.insert(lines, string.format(
            "drawLabel('%s', Math.floor(%d * scaleX), imgH - Math.floor(%d * scaleY), %s, %s, %s)",
            text, rect.left, rect.top, rgb[1] / 255, rgb[2] / 255, rgb[3] / 255))
        end
      end
    end
  end
```

- [ ] **Step 4: Pass the flag and re-render on toggle**

In `createUnifiedImageView` (line 869-873), add `props.showISO` as the last argument:

```lua
      outputPath = FOVRenderer.renderMacOverlay(
        basePath, rects, enabledFLs,
        dw, dh, iw, ih,
        renderCount.value, highlightFL, activeCrop, props.showISO
      )
```

Next to `props:addObserver("highlightFL", ...)` (line 914), add:

```lua
  props:addObserver("showISO", function()
    scheduleRender()
  end)
```

- [ ] **Step 5: Syntax check and unit tests**

Run: `luac -p fovoverlay.lrplugin/FOVRenderer.lua && lua tests/test_iso.lua`
Expected: exit 0, `0 failed`.

- [ ] **Step 6: Manual check on macOS in Lightroom**

Reload the plugin (File > Plug-in Manager > FOV Overlay > Reload Plug-in), then open Show FOV Guides on:
1. An uncropped photo with a known ISO: each visible rectangle has a label like `400mm  ≈ISO 3200 (+1.9 EV)` in its color at the top-left corner. Toggling "Show ISO equiv" removes and restores labels, header suffix and legend values.
2. A cropped photo: header shows `≈ISO … equiv (+x.x EV)`. Switching Full Frame/Cropped keeps the legend values relative to the full sensor.
3. A tilted crop: labels sit at the rotated rect's upper-left corner.
4. Highlight crop set: labels remain readable over dimming.
5. Four adjacent FLs checked (e.g. 400/420/450/500): close labels are skipped, legend still lists all values.

If the JXA render fails (blank overlay, or the "Showing corner markers instead" warning appears), run the last generated script by hand to see the JavaScript error. Lightroom writes it to its temp folder as `fov_draw.js`:

```bash
osascript -l JavaScript "$TMPDIR/fov_draw.js"
```

- [ ] **Step 7: Commit**

```bash
git add fovoverlay.lrplugin/FOVRenderer.lua
git commit -m "feat: draw crop-equivalent ISO labels on macOS overlay"
```

---

### Task 5: Draw ISO labels on the Windows overlay

**Files:**
- Modify: `fovoverlay.lrplugin/FOVRenderer.lua` (`renderWindowsOverlay` at line 641; call site line 863)

- [ ] **Step 1: Add the `showLabels` parameter**

```lua
function FOVRenderer.renderWindowsOverlay(baseImagePath, allCropRects, enabledFLs, displayWidth, displayHeight, workingWidth, workingHeight, renderCount, highlightFL, cropRect, showLabels)
```

- [ ] **Step 2: Emit label drawing after the highlight dimming**

Insert immediately before `table.insert(lines, '$g.Dispose()')` (line 761):

```lua
  -- Crop-equivalent ISO labels at each rect's top-left corner
  if showLabels then
    local labelFont = math.max(11, math.floor(displayWidth / 75))
    local labelHeight = math.floor(labelFont * 1.4) + 4
    local labeled = FOVCalculator.selectLabeledFLs(
      allCropRects, enabledFLs, displayHeight / workingHeight, labelHeight)

    table.insert(lines, '$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit')
    table.insert(lines, string.format('$lblScale = $img.Width / %d', displayWidth))
    table.insert(lines, string.format(
      '$lblFont = New-Object System.Drawing.Font("Segoe UI", [float](%d * $lblScale), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)',
      labelFont))
    table.insert(lines, '$lblBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(153, 0, 0, 0))')

    for i, rect in ipairs(allCropRects) do
      if labeled[rect.focalLength] and rect.isoLabel then
        local colorIndex = rect.colorIndex or (((i - 1) % #FOVRenderer.colorNames) + 1)
        local rgb = FOVRenderer.colorRGB[FOVRenderer.colorNames[colorIndex]]
        -- PowerShell double-quoted string: U+2248 via subexpression (script file is not UTF-8 safe on PS 5.1)
        local text = rect.isoLabel:gsub("{approx}", "$([char]0x2248)")
        if rect.rotatedCorners then
          local ul = rect.rotatedCorners[1]
          table.insert(lines, string.format('$lx = [math]::Floor(%s * $img.Width) + $pw + 2', ul[1]))
          table.insert(lines, string.format('$ly = [math]::Floor(%s * $img.Height) + $pw + 2', ul[2]))
        else
          table.insert(lines, string.format('$lx = [math]::Floor(%d * $scaleX) + $pw + 2', rect.left))
          table.insert(lines, string.format('$ly = [math]::Floor(%d * $scaleY) + $pw + 2', rect.top))
        end
        table.insert(lines, '$txt = "' .. text .. '"')
        table.insert(lines, '$sz = $g.MeasureString($txt, $lblFont)')
        table.insert(lines, '$g.FillRectangle($lblBg, $lx, $ly, ($sz.Width + 8), ($sz.Height + 4))')
        table.insert(lines, string.format(
          '$lb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, %d, %d, %d))',
          rgb[1], rgb[2], rgb[3]))
        table.insert(lines, '$g.DrawString($txt, $lblFont, $lb, ($lx + 4), ($ly + 2))')
        table.insert(lines, '$lb.Dispose()')
      end
    end

    table.insert(lines, '$lblFont.Dispose()')
    table.insert(lines, '$lblBg.Dispose()')
  end
```

- [ ] **Step 3: Pass the flag at the Windows call site**

```lua
      outputPath = FOVRenderer.renderWindowsOverlay(
        basePath, rects, enabledFLs,
        dw, dh, iw, ih,
        renderCount.value, highlightFL, activeCrop, props.showISO
      )
```

- [ ] **Step 4: Syntax check**

Run: `luac -p fovoverlay.lrplugin/FOVRenderer.lua`
Expected: exit 0.

- [ ] **Step 5: Manual check on Windows in Lightroom**

Repeat the five scenarios from Task 4 Step 6 on a Windows machine. Confirm the `≈` glyph renders (not `?` or mojibake).

- [ ] **Step 6: Commit**

```bash
git add fovoverlay.lrplugin/FOVRenderer.lua
git commit -m "feat: draw crop-equivalent ISO labels on Windows overlay"
```

---

### Task 6: Docs

**Files:**
- Modify: `fovoverlay.lrplugin/FOVInfoProvider.lua:246`
- Modify: `README.md` (Features list and a new section after "Understanding the Overlays")

- [ ] **Step 1: About text**

Replace the About formula text at `FOVInfoProvider.lua:246` with:

```lua
          title = "Calculates crop areas using the formula:\nCrop Ratio = Target FL / Original FL\n\n" ..
                  "Crop-equivalent ISO (approx.):\nISO \195\151 (full frame area \195\183 crop area)",
```

- [ ] **Step 2: README**

Add to the Features list:

```markdown
- **Crop-equivalent ISO** — each overlay shows the approximate ISO an uncropped frame would need to look as noisy at the same output size (after Steve Perry's crop-vs-ISO guidance)
```

Add a section after "Understanding the Overlays":

```markdown
### Crop-Equivalent ISO

Cropping does not add noise per pixel, but a cropped image has to be enlarged more to reach the same print or screen size, so its noise is enlarged too. Wildlife photographer Steve Perry explains this in [The Cropping Epidemic](https://backcountrygallery.com/the-cropping-epidemic/) and [Cropping? Better Drop Your ISO!](https://backcountrygallery.com/cropping-better-drop-your-iso/).

The plugin estimates it as:

    Equivalent ISO = Shot ISO × (Full frame area ÷ Crop area)
    Extra stops    = log2(Full frame area ÷ Crop area)

A 2× crop (for example 300mm cropped to 600mm) at ISO 1600 looks roughly like ISO 6400 uncropped (+2 EV). Values are rounded to the nearest 1/3-stop ISO and marked with ≈.

This is an approximation. It assumes the same camera and the same output size, and ignores read noise, dynamic range and AI denoise. It compares against your camera's own full sensor, not against a full-frame camera.

Toggle it with **Show ISO equiv** in the dialog.
```

- [ ] **Step 3: Commit**

```bash
git add README.md fovoverlay.lrplugin/FOVInfoProvider.lua
git commit -m "docs: document crop-equivalent ISO"
```

---

## Decisions taken after review (2026-10-06, maintainer answered "yes to all")

These supersede the matching parts of the tasks above; the implementation follows them.

1. **Full-frame equivalence added.** `equivalentISO` takes an optional fourth argument `sensorCropFactor`; when > 1 the ratio is multiplied by its square. The dialog has a "vs full frame" checkbox (`props.isoFullFrame`, visible only on crop-sensor bodies). Toggling it re-annotates rects, rebuilds header and legend, and re-renders. Labels and header get an " FF" suffix while it is on. Tests e4–e6 cover it.
2. **Version bumped to 1.7.0** in `Info.lua`.
3. **Short on-image labels.** The overlay shows `500mm  ≈ISO 4000` (no EV). The header keeps the EV delta.
4. Dialog observers are consolidated in a `refreshHeader` helper next to `annotateISO`/`updateLegendISO`.
