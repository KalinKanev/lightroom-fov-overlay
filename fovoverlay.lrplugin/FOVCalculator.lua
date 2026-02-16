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
function FOVCalculator.calculateCropRect(originalFL, targetFL, imageWidth, imageHeight)
  if targetFL <= originalFL then
    return nil -- Can only simulate longer focal lengths
  end

  local cropRatio = targetFL / originalFL
  local cropWidth = imageWidth / cropRatio
  local cropHeight = imageHeight / cropRatio
  local offsetX = (imageWidth - cropWidth) / 2
  local offsetY = (imageHeight - cropHeight) / 2

  local originalMP = (imageWidth * imageHeight) / 1000000
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
function FOVCalculator.calculateAllCropRects(originalFL, targetFLs, imageWidth, imageHeight)
  local results = {}

  for _, targetFL in ipairs(targetFLs) do
    local rect = FOVCalculator.calculateCropRect(originalFL, targetFL, imageWidth, imageHeight)
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

return FOVCalculator
