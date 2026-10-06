--[[
  FOVCalculator.lua

  Handles focal length and crop calculations for FOV overlay visualization.
--]]

local FOVCalculator = {}

--[[
  Parse focal length string from Lightroom metadata
  Input: "300 mm" or "300mm"
  Output: 300 (number)
--]]
function FOVCalculator.parseFocalLength(focalLengthStr)
  if not focalLengthStr then return nil end
  local fl = tonumber(focalLengthStr:match("(%d+%.?%d*)"))
  return fl
end

--[[
  Parse dimensions string from Lightroom metadata
  Input: "6000 x 4000" or "6000x4000"
  Output: width, height (numbers)
--]]
function FOVCalculator.parseDimensions(dimensionsStr)
  if not dimensionsStr then return nil, nil end
  local w, h = dimensionsStr:match("(%d+)%s*x%s*(%d+)")
  return tonumber(w), tonumber(h)
end

--[[
  Calculate the crop rectangle for a target focal length

  Parameters:
    originalFL: Original focal length in mm
    targetFL: Target (simulated) focal length in mm
    imageWidth: Original image width in pixels
    imageHeight: Original image height in pixels

  Returns table with:
    focalLength: Target focal length
    cropRatio: The crop ratio (targetFL / originalFL)
    width: Crop rectangle width
    height: Crop rectangle height
    left: X offset (centered)
    top: Y offset (centered)
    megapixels: Remaining megapixels after crop
    percentage: Percentage of original dimensions
--]]
function FOVCalculator.calculateCropRect(originalFL, targetFL, imageWidth, imageHeight, centerX, centerY)
  if targetFL <= originalFL then
    return nil -- Can only simulate longer focal lengths
  end

  local cropRatio = targetFL / originalFL
  local cropWidth = imageWidth / cropRatio
  local cropHeight = imageHeight / cropRatio

  -- Center on the given point (defaults to image center)
  local cx = centerX or (imageWidth / 2)
  local cy = centerY or (imageHeight / 2)
  local offsetX = cx - cropWidth / 2
  local offsetY = cy - cropHeight / 2

  -- Clamp to image bounds
  if offsetX < 0 then offsetX = 0 end
  if offsetY < 0 then offsetY = 0 end
  if offsetX + cropWidth > imageWidth then offsetX = imageWidth - cropWidth end
  if offsetY + cropHeight > imageHeight then offsetY = imageHeight - cropHeight end

  local croppedMP = (cropWidth * cropHeight) / 1000000
  local percentage = (1 / cropRatio) * 100

  return {
    focalLength = targetFL,
    cropRatio = cropRatio,
    width = math.floor(cropWidth),
    height = math.floor(cropHeight),
    left = math.floor(offsetX),
    top = math.floor(offsetY),
    right = math.floor(offsetX + cropWidth),
    bottom = math.floor(offsetY + cropHeight),
    megapixels = math.floor(croppedMP * 10) / 10,
    percentage = math.floor(percentage)
  }
end

--[[
  Calculate crop rectangles for multiple target focal lengths

  Parameters:
    originalFL: Original focal length in mm
    targetFLs: Array of target focal lengths
    imageWidth: Original image width in pixels
    imageHeight: Original image height in pixels

  Returns array of crop rectangle tables
--]]
function FOVCalculator.calculateAllCropRects(originalFL, targetFLs, imageWidth, imageHeight, centerX, centerY)
  local results = {}

  for _, targetFL in ipairs(targetFLs) do
    local rect = FOVCalculator.calculateCropRect(originalFL, targetFL, imageWidth, imageHeight, centerX, centerY)
    if rect then
      table.insert(results, rect)
    end
  end

  -- Sort by focal length (smallest first = outermost rectangle)
  table.sort(results, function(a, b) return a.focalLength < b.focalLength end)

  return results
end

--[[
  Generate suggested target focal lengths based on original

  Parameters:
    originalFL: Original focal length in mm

  Returns array of suggested target focal lengths
--]]
function FOVCalculator.suggestTargetFocalLengths(originalFL)
  local suggestions = {}

  -- Common multipliers: 1.4x, 1.5x, 2x, 3x, 4x
  local multipliers = { 1.4, 1.5, 2.0, 3.0, 4.0 }

  for _, mult in ipairs(multipliers) do
    local targetFL = math.floor(originalFL * mult)
    -- Round to nearest "nice" number
    if targetFL >= 100 then
      targetFL = math.floor(targetFL / 50) * 50 -- Round to nearest 50
    elseif targetFL >= 50 then
      targetFL = math.floor(targetFL / 10) * 10 -- Round to nearest 10
    end
    table.insert(suggestions, targetFL)
  end

  return suggestions
end

--[[
  Calculate the field of view angle

  Parameters:
    focalLength: Focal length in mm
    sensorDimension: Sensor dimension in mm (width, height, or diagonal)

  Returns: Field of view angle in degrees
--]]
function FOVCalculator.calculateFOVAngle(focalLength, sensorDimension)
  -- AOV = 2 * arctan(d / (2 * f))
  local radians = 2 * math.atan(sensorDimension / (2 * focalLength))
  local degrees = radians * (180 / math.pi)
  return math.floor(degrees * 100) / 100
end

-- Common sensor dimensions (in mm)
FOVCalculator.sensorSizes = {
  fullFrame = { width = 36, height = 24, diagonal = 43.27 },
  apscSony = { width = 23.5, height = 15.6, diagonal = 28.21 },
  apscCanon = { width = 22.3, height = 14.9, diagonal = 26.82 },
  microFourThirds = { width = 17.3, height = 13.0, diagonal = 21.64 },
}

--[[
  Calculate depth of field information

  Parameters:
    focalLengthMM: Focal length in mm
    fNumber: F-number (aperture)
    distanceM: Focus distance in meters
    cropFactor: Crop factor (1.0 for full-frame, 1.5 for APS-C, etc.)

  Returns table with:
    near: Near DOF distance in meters (nil if at/beyond infinity threshold)
    far: Far DOF distance in meters (nil if at/beyond infinity threshold or focus distance beyond hyperfocal)
    span: DOF span (far - near) in meters (nil if at/beyond infinity threshold or focus distance beyond hyperfocal)
    hyperfocal: Hyperfocal distance in meters
    isInfinity: Boolean indicating if focus distance is at infinity

  Returns nil if inputs are invalid
--]]
local INFINITY_THRESHOLD_M = 500  -- meters; values above this are treated as ∞

function FOVCalculator.calculateDoF(focalLengthMM, fNumber, distanceM, cropFactor)
  if not focalLengthMM or not fNumber or not distanceM or not cropFactor then return nil end
  if focalLengthMM <= 0 or fNumber <= 0 or distanceM <= 0 or cropFactor <= 0 then return nil end

  local fl  = focalLengthMM
  local coc = 0.029 / cropFactor        -- circle of confusion (mm)
  local H   = (fl * fl) / (fNumber * coc) + fl  -- hyperfocal distance (mm)
  local hyperfocal = H / 1000           -- meters

  if distanceM >= INFINITY_THRESHOLD_M then
    return { near = nil, far = nil, span = nil, hyperfocal = hyperfocal, isInfinity = true }
  end

  local d    = distanceM * 1000         -- convert to mm
  local near = (H * d) / (H + d) / 1000  -- meters

  local far, span
  if d >= H then
    far  = nil
    span = nil
  else
    far  = (H * d) / (H - d) / 1000    -- meters
    span = far - near
  end

  return { near = near, far = far, span = span, hyperfocal = hyperfocal, isInfinity = false }
end

--[[
  Pick the focal lengths to pre-select: the `count` shortest ones that are
  strictly longer than baseFL. For a cropped photo pass the crop's
  equivalent FL so the defaults are tighter than the current crop.

  Returns a set { [focalLength] = true }.
--]]
function FOVCalculator.defaultSelectedFLs(focalLengths, baseFL, count)
  local result, n = {}, 0
  for _, fl in ipairs(focalLengths) do
    if fl > baseFL and n < count then
      result[fl] = true
      n = n + 1
    end
  end
  return result
end

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
    sensorCropFactor: Optional. When > 1, also converts to full-frame
      equivalence by multiplying the ratio by sensorCropFactor^2
      (APS-C 1.5x: ISO 800 behaves like full-frame ISO ~1800).

  Returns table { ratio, stops, iso, display } or nil for invalid areas.
  iso and display are nil when baseISO is nil.
--]]
function FOVCalculator.equivalentISO(baseISO, fullArea, cropArea, sensorCropFactor)
  if not fullArea or not cropArea or fullArea <= 0 or cropArea <= 0 then return nil end
  local ratio = fullArea / cropArea
  if sensorCropFactor and sensorCropFactor > 1 then
    ratio = ratio * sensorCropFactor * sensorCropFactor
  end
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
return FOVCalculator
