--[[
  FOVOverlayDialog.lua

  Main entry point for the FOV Overlay plugin.
  Creates a dialog showing the selected photo with FOV crop overlays.
  Shows standard focal lengths with toggleable checkboxes.
--]]

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'
local LrColor = import 'LrColor'
local LrBinding = import 'LrBinding'
local LrSystemInfo = import 'LrSystemInfo'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

local FOVCalculator = require 'FOVCalculator'
local FOVRenderer = require 'FOVRenderer'

-- Standard focal lengths in photography
local standardFocalLengths = {
  24, 28, 35, 50, 70, 85, 100, 135, 200, 300, 400, 420, 450, 500, 560, 600, 800, 840, 1000, 1200
}

--[[
  Query ExifTool for subject distance using brand-specific tags,
  mirroring the approach of the Focus Points plugin.
  Returns a formatted distance string, or nil if unavailable.
--]]
local function getSubjectDistance(photo, exiftoolPath)
  local make = (photo:getFormattedMetadata("cameraMake") or ""):lower()
  local originalPath = photo:getRawMetadata("path")
  local singleQuoteWrap = '\'"\'"\''

  local isCanon   = make:find("canon")   ~= nil
  local isNikon   = make:find("nikon")   ~= nil
  local isSony    = make:find("sony")    ~= nil
  local isOlympus = make:find("olympus") ~= nil or make:find("om digital") ~= nil

  local tagArgs
  if     isCanon   then tagArgs = "-FocusDistanceUpper -FocusDistanceLower"
  elseif isNikon   then tagArgs = "-FocusDistance"
  elseif isSony    then tagArgs = "-FocusDistance2"
  elseif isOlympus then tagArgs = "-FocusDistance"
  else                  tagArgs = "-SubjectDistance"
  end

  -- Use -s format (TagName: Value) so parsing is unambiguous regardless of tag order
  local results = {}
  if WIN_ENV then
    local tempPath    = LrPathUtils.getStandardFilePath("temp")
    local batPath     = LrPathUtils.child(tempPath, "fov_dist.bat")
    local distOutPath = LrPathUtils.child(tempPath, "fov_dist_out.txt")
    local batFile = io.open(batPath, "w+b")
    batFile:write(string.format('@"%s" -s %s "%s" > "%s"',
      exiftoolPath, tagArgs, originalPath, distOutPath))
    batFile:close()
    LrTasks.execute('"' .. batPath .. '"')
    local f_in = io.open(distOutPath, "r")
    if f_in then
      for line in f_in:lines() do
        local key, val = line:match("^(%S+)%s*:%s*(.+)$")
        if key and val then results[key] = val:match("^%s*(.-)%s*$") end
      end
      f_in:close()
    end
  else
    local et  = exiftoolPath:gsub("'", singleQuoteWrap)
    local op  = originalPath:gsub("'", singleQuoteWrap)
    local pipe = io.popen(string.format("'%s' -s %s '%s' 2>/dev/null", et, tagArgs, op))
    if pipe then
      for line in pipe:lines() do
        local key, val = line:match("^(%S+)%s*:%s*(.+)$")
        if key and val then results[key] = val:match("^%s*(.-)%s*$") end
      end
      pipe:close()
    end
  end

  local function valid(v) return v and v ~= "" and v ~= "-" and v ~= "0" and v ~= "0.00 m" end

  if isCanon then
    local upper, lower = results["FocusDistanceUpper"], results["FocusDistanceLower"]
    if valid(upper) and valid(lower) then
      return upper == lower and upper or (lower .. " \226\128\147 " .. upper)
    end
    return valid(upper) and upper or (valid(lower) and lower or nil)
  elseif isSony    then return valid(results["FocusDistance2"]) and results["FocusDistance2"] or nil
  elseif isNikon or isOlympus then return valid(results["FocusDistance"])  and results["FocusDistance"]  or nil
  else                             return valid(results["SubjectDistance"]) and results["SubjectDistance"] or nil
  end
end

-- Main function called from menu
LrTasks.startAsyncTask(function()
  LrFunctionContext.callWithContext("FOVOverlay", function(context)

    local catalog = LrApplication.activeCatalog()
    local photo = catalog:getTargetPhoto()

    if not photo then
      LrDialogs.message("FOV Overlay", "Please select a photo first.", "info")
      return
    end

    -- Get photo metadata
    local focalLengthStr = photo:getFormattedMetadata("focalLength")
    local dimensionsStr = photo:getFormattedMetadata("dimensions")

    local lensFL = FOVCalculator.parseFocalLength(focalLengthStr)
    local imageWidth, imageHeight = FOVCalculator.parseDimensions(dimensionsStr)

    if not lensFL then
      LrDialogs.message("FOV Overlay", "Could not read focal length from photo metadata.\n\nFocal Length: " .. tostring(focalLengthStr), "warning")
      return
    end

    -- Get 35mm equivalent focal length for correct FOV on crop sensors
    local fl35mm = photo:getRawMetadata("focalLength35mm")
    if not fl35mm or fl35mm <= 0 then
      -- Try ExifTool as fallback (covers Canon and other cameras that don't write this EXIF tag)
      local exifToolPath = FOVRenderer.findExifTool()
      if exifToolPath then
        local filePath = photo:getRawMetadata("path")
        if filePath then
          local tmpDir = LrPathUtils.getStandardFilePath("temp")
          local tmpOut = LrPathUtils.child(tmpDir, "fov_fl35mm.txt")
          local cmd
          if WIN_ENV then
            local scriptPath = LrPathUtils.child(tmpDir, "fov_fl35mm.bat")
            local script = string.format(
              '@"%s" -s3 -FocalLengthIn35mmFormat "%s" > "%s"',
              exifToolPath, filePath, tmpOut)
            local sf = io.open(scriptPath, "w+b")
            if sf then
              sf:write(script)
              sf:close()
            end
            cmd = '"' .. scriptPath .. '"'
          else
            local singleQuoteWrap = '\'"\'"\''
            local et = exifToolPath:gsub("'", singleQuoteWrap)
            local rf = filePath:gsub("'", singleQuoteWrap)
            cmd = string.format("'%s' -s3 -FocalLengthIn35mmFormat '%s' > '%s'",
              et, rf, tmpOut)
          end
          LrTasks.execute(cmd)
          if LrFileUtils.exists(tmpOut) then
            local fh = io.open(tmpOut, "r")
            if fh then
              local result = fh:read("*a")
              fh:close()
              if result then
                local val = tonumber(result:match("(%d+%.?%d*)"))
                if val and val > 0 then
                  fl35mm = val
                end
              end
            end
            LrFileUtils.delete(tmpOut)
          end
        end
      end
    end

    -- Use 35mm equiv as the base for FOV calculations; fall back to lens FL
    local originalFL = (fl35mm and fl35mm > 0) and math.floor(fl35mm + 0.5) or lensFL
    local isCropSensor = (originalFL > lensFL + 0.5)

    if not imageWidth or not imageHeight then
      LrDialogs.message("FOV Overlay", "Could not read image dimensions from photo metadata.", "warning")
      return
    end

    -- Check for crop in develop settings
    local devSettings = photo:getDevelopSettings()
    local cropLeft = devSettings.CropLeft or 0
    local cropTop = devSettings.CropTop or 0
    local cropRight = devSettings.CropRight or 1
    local cropBottom = devSettings.CropBottom or 1

    local isCropped = (cropLeft > 0.001 or cropTop > 0.001 or cropRight < 0.999 or cropBottom < 0.999)

    -- Crop rect for the renderer, nil if not cropped.
    -- Per John R. Ellis's algorithm: (CropLeft, CropTop) and (CropRight, CropBottom)
    -- are two OPPOSITE CORNERS of the already-rotated crop rectangle in normalized
    -- coordinates. Y-axis is inverted in develop coords: y_px = (1 - cropVal) * height.
    -- CropAngle rotation is around the crop rectangle's own center.
    local cropAngle = devSettings.CropAngle or 0
    local cropRect = nil
    local actualCropPixW, actualCropPixH

    local function rotatePoint(px, py, cx, cy, cosA, sinA)
      local dx, dy = px - cx, py - cy
      return cx + dx * cosA - dy * sinA,
             cy + dx * sinA + dy * cosA
    end

    if isCropped and math.abs(cropAngle) >= 0.01 then
      -- Step 1: Convert the two known corners to develop pixel coords (Y inverted)
      local ulx = cropLeft * imageWidth
      local uly = (1 - cropTop) * imageHeight
      local lrx = cropRight * imageWidth
      local lry = (1 - cropBottom) * imageHeight

      -- Step 2: Center of crop rectangle
      local cx = (ulx + lrx) / 2
      local cy = (uly + lry) / 2

      -- Step 3: angle = -CropAngle (negate for math convention: positive = CCW)
      local a = -cropAngle

      -- Step 4: Un-rotate the two known corners by -a around center
      local negRad = math.rad(-a)
      local negCos, negSin = math.cos(negRad), math.sin(negRad)
      local uulx, uuly = rotatePoint(ulx, uly, cx, cy, negCos, negSin)
      local ulrx, ulry = rotatePoint(lrx, lry, cx, cy, negCos, negSin)

      -- Step 5: Derive the other two unrotated corners
      local ullx, ully = uulx, ulry  -- unrotated lower-left
      local uurx, uury = ulrx, uuly  -- unrotated upper-right

      -- Actual crop dimensions from the un-rotated rectangle
      actualCropPixW = math.abs(ulrx - uulx)
      actualCropPixH = math.abs(uuly - ulry)

      -- Step 6: Rotate all four corners by +a around center
      local posRad = math.rad(a)
      local posCos, posSin = math.cos(posRad), math.sin(posRad)
      local c1x, c1y = rotatePoint(uulx, uuly, cx, cy, posCos, posSin) -- ul
      local c2x, c2y = rotatePoint(uurx, uury, cx, cy, posCos, posSin) -- ur
      local c3x, c3y = rotatePoint(ulrx, ulry, cx, cy, posCos, posSin) -- lr
      local c4x, c4y = rotatePoint(ullx, ully, cx, cy, posCos, posSin) -- ll

      -- Convert back to normalized renderer coords (0-1, Y downward)
      cropRect = { corners = {
        { c1x / imageWidth, 1 - c1y / imageHeight },  -- ul
        { c2x / imageWidth, 1 - c2y / imageHeight },  -- ur
        { c3x / imageWidth, 1 - c3y / imageHeight },  -- lr
        { c4x / imageWidth, 1 - c4y / imageHeight },  -- ll
      }}
    elseif isCropped then
      -- No rotation: crop values directly define the rectangle
      cropRect = { corners = {
        { cropLeft, cropTop },
        { cropRight, cropTop },
        { cropRight, cropBottom },
        { cropLeft, cropBottom },
      }}
      actualCropPixW = (cropRight - cropLeft) * imageWidth
      actualCropPixH = (cropBottom - cropTop) * imageHeight
    end

    -- Compute cropped dimensions and effective FL for cropped view mode
    local croppedWidth, croppedHeight, effectiveFL
    if isCropped then
      croppedWidth = math.floor(actualCropPixW)
      croppedHeight = math.floor(actualCropPixH)
      effectiveFL = math.floor(originalFL * imageWidth / actualCropPixW + 0.5)
    else
      croppedWidth = imageWidth
      croppedHeight = imageHeight
      effectiveFL = originalFL
    end

    -- Extract focus distance using brand-specific ExifTool tags
    local subjectDistance = nil
    local exiftoolPath = FOVRenderer.findExifTool()
    if exiftoolPath then
      subjectDistance = getSubjectDistance(photo, exiftoolPath)
    end

    -- Create observable properties
    local props = LrBinding.makePropertyTable(context)

    -- Whether to show distance in header and image overlay
    props.showDistance = (subjectDistance ~= nil)

    -- View mode: "full" (uncropped) or "cropped"
    props.viewMode = "full"
    props.viewModeItems = isCropped
      and { { title = "Full Frame", value = "full" }, { title = "Cropped", value = "cropped" } }
      or  { { title = "Full Frame", value = "full" } }

    -- Append distance to a header string when the toggle is on
    local function withDist(s)
      if subjectDistance and props.showDistance then
        return s .. "  |  \226\166\191 " .. subjectDistance
      end
      return s
    end

    -- Header text (reactive to viewMode and showDistance)
    local function buildFullFrameHeader()
      local flLabel
      if isCropSensor then
        flLabel = string.format("Lens: %dmm (\226\137\136%dmm FF)", lensFL, originalFL)
      else
        flLabel = string.format("Original: %dmm", originalFL)
      end
      if isCropped then
        return withDist(string.format("%s  |  Cropped to %dmm equiv  |  %d \195\151 %d  |  %.1f MP",
          flLabel, effectiveFL, croppedWidth, croppedHeight, (croppedWidth * croppedHeight) / 1000000))
      else
        return withDist(string.format("%s  |  %d \195\151 %d  |  %.1f MP",
          flLabel, imageWidth, imageHeight, (imageWidth * imageHeight) / 1000000))
      end
    end

    local function buildCroppedHeader()
      local flLabel
      if isCropSensor then
        flLabel = string.format("Lens: %dmm (\226\137\136%dmm FF)", lensFL, originalFL)
      else
        flLabel = string.format("Shot at %dmm", originalFL)
      end
      return withDist(string.format("%s  |  Cropped to %dmm equiv  |  %d \195\151 %d  |  %.1f MP",
        flLabel, effectiveFL, croppedWidth, croppedHeight, (croppedWidth * croppedHeight) / 1000000))
    end

    props.headerText = buildFullFrameHeader()

    -- Initialize checkbox states and per-FL enabled properties
    local enabledCount = 0
    for _, fl in ipairs(standardFocalLengths) do
      props["enabled_" .. fl] = fl > originalFL
      if fl > originalFL then
        enabledCount = enabledCount + 1
        props["show_" .. fl] = (enabledCount <= 4)
      else
        props["show_" .. fl] = false
      end
    end

    -- Highlight crop dropdown state
    props.highlightFL = 0  -- 0 = None
    props.highlightFLItems = { { title = "None", value = 0 } }
    props.renderWarning = ""

    -- Get the active base FL for the current view mode
    local function getActiveFL()
      if props.viewMode == "cropped" then
        return effectiveFL
      else
        return originalFL
      end
    end

    -- Rebuild the highlight dropdown items from currently-checked and enabled FLs
    local function rebuildHighlightItems()
      local activeFL = getActiveFL()
      local items = { { title = "None", value = 0 } }
      for _, fl in ipairs(standardFocalLengths) do
        if fl > activeFL and props["show_" .. fl] then
          table.insert(items, { title = string.format("%dmm", fl), value = fl })
        end
      end
      props.highlightFLItems = items

      -- If the currently highlighted FL was unchecked, reset to None
      local found = false
      for _, item in ipairs(items) do
        if item.value == props.highlightFL then
          found = true
          break
        end
      end
      if not found then
        props.highlightFL = 0
      end
    end

    -- Update checkbox enabled states and header when view mode changes
    local function onViewModeChanged()
      local activeFL = getActiveFL()
      if props.viewMode == "cropped" then
        props.headerText = buildCroppedHeader()
      else
        props.headerText = buildFullFrameHeader()
      end

      -- Update enabled states
      local newlyEnabled = {}
      for _, fl in ipairs(standardFocalLengths) do
        local wasEnabled = props["enabled_" .. fl]
        local nowEnabled = fl > activeFL
        props["enabled_" .. fl] = nowEnabled
        -- Uncheck FLs that become unavailable
        if wasEnabled and not nowEnabled then
          props["show_" .. fl] = false
        end
        -- Track newly enabled FLs (were disabled, now enabled)
        if not wasEnabled and nowEnabled then
          table.insert(newlyEnabled, fl)
        end
      end

      -- Always re-select the 4 widest (closest to base FL) available FOVs
      local count = 0
      for _, fl in ipairs(standardFocalLengths) do
        if fl > activeFL then
          count = count + 1
          props["show_" .. fl] = (count <= 4)
        end
      end

      rebuildHighlightItems()
    end

    -- Observe checkbox changes to rebuild highlight dropdown
    for _, fl in ipairs(standardFocalLengths) do
      props:addObserver("show_" .. fl, function()
        rebuildHighlightItems()
      end)
    end

    -- Observe view mode changes
    props:addObserver("viewMode", function()
      onViewModeChanged()
    end)

    -- Observe distance toggle: rebuild header only (overlay visibility is a direct binding)
    props:addObserver("showDistance", function()
      if props.viewMode == "cropped" then
        props.headerText = buildCroppedHeader()
      else
        props.headerText = buildFullFrameHeader()
      end
    end)

    -- Build initial dropdown items
    rebuildHighlightItems()

    -- Derive max display size from LR application window
    local appWidth, appHeight = LrSystemInfo.appWindowSize()
    local maxDisplayWidth = math.floor(appWidth * 0.7)
    local maxDisplayHeight = math.floor(appHeight * 0.6)

    -- Display dimensions for full-frame view
    local aspectRatio = imageWidth / imageHeight
    local displayWidth, displayHeight
    if aspectRatio > (maxDisplayWidth / maxDisplayHeight) then
      displayWidth = maxDisplayWidth
      displayHeight = math.floor(maxDisplayWidth / aspectRatio)
    else
      displayHeight = maxDisplayHeight
      displayWidth = math.floor(maxDisplayHeight * aspectRatio)
    end

    -- Display dimensions for cropped view
    local croppedAspectRatio = croppedWidth / croppedHeight
    local croppedDisplayWidth, croppedDisplayHeight
    if croppedAspectRatio > (maxDisplayWidth / maxDisplayHeight) then
      croppedDisplayWidth = maxDisplayWidth
      croppedDisplayHeight = math.floor(maxDisplayWidth / croppedAspectRatio)
    else
      croppedDisplayHeight = maxDisplayHeight
      croppedDisplayWidth = math.floor(maxDisplayHeight * croppedAspectRatio)
    end

    -- Crop center in original image pixel coordinates (for centering FOV guides on the crop)
    local cropCenterX, cropCenterY
    if isCropped and cropRect then
      -- Average the 4 corners to get the center in original image coords
      local sumX, sumY = 0, 0
      for _, c in ipairs(cropRect.corners) do
        sumX = sumX + c[1]
        sumY = sumY + c[2]
      end
      cropCenterX = (sumX / 4) * imageWidth
      cropCenterY = (sumY / 4) * imageHeight
    end

    -- Crop rects for full-frame view (relative to full sensor, using originalFL)
    -- Center on the crop center when image is cropped, otherwise image center
    local allCropRects = FOVCalculator.calculateAllCropRects(originalFL, standardFocalLengths, imageWidth, imageHeight, cropCenterX, cropCenterY)

    -- Crop rects for cropped view (relative to cropped area, using effectiveFL)
    local croppedCropRects = isCropped
      and FOVCalculator.calculateAllCropRects(effectiveFL, standardFocalLengths, croppedWidth, croppedHeight)
      or allCropRects

    -- Assign fixed color index per FL based on full-frame position (consistent across view modes)
    local flToColorIndex = {}
    for i, rect in ipairs(allCropRects) do
      flToColorIndex[rect.focalLength] = ((i - 1) % #FOVRenderer.colorNames) + 1
      rect.colorIndex = flToColorIndex[rect.focalLength]
    end
    for _, rect in ipairs(croppedCropRects) do
      rect.colorIndex = flToColorIndex[rect.focalLength] or ((1 - 1) % #FOVRenderer.colorNames) + 1
    end

    -- When crop is tilted, rotate FOV guide rects to match the crop orientation
    if isCropped and math.abs(cropAngle) >= 0.01 and cropCenterX then
      local rad = math.rad(cropAngle)
      local cosA = math.cos(rad)
      local sinA = math.sin(rad)

      for _, rect in ipairs(allCropRects) do
        -- Rect corners in pixel space
        local l, t = rect.left, rect.top
        local r, b = rect.left + rect.width, rect.top + rect.height
        local rawCorners = { {l,t}, {r,t}, {r,b}, {l,b} }

        -- Rotate around crop center in pixel space
        local rotCorners = {}
        for _, c in ipairs(rawCorners) do
          local dx = c[1] - cropCenterX
          local dy = c[2] - cropCenterY
          local rx = cosA * dx - sinA * dy + cropCenterX
          local ry = sinA * dx + cosA * dy + cropCenterY
          table.insert(rotCorners, { rx / imageWidth, ry / imageHeight })
        end
        rect.rotatedCorners = rotCorners
      end
    end

    -- Build the dialog
    local f = LrView.osFactory()

    -- Create checkbox rows (up to 4 per row)
    local checkboxRows = {}
    local currentRow = {}
    local colorNames = FOVRenderer.colorNames
    local legendColors = {
      green = LrColor(0, 0.78, 0),
      yellow = LrColor(1, 0.78, 0),
      orange = LrColor(1, 0.5, 0),
      red = LrColor(1, 0.2, 0.2),
      cyan = LrColor(0, 0.78, 0.86),
      magenta = LrColor(0.86, 0, 0.86),
      blue = LrColor(0.31, 0.47, 1),
      lime = LrColor(0.63, 1, 0),
      pink = LrColor(1, 0.47, 0.71),
      white = LrColor(0.94, 0.94, 0.94),
    }

    -- Build checkbox items into columns (top-to-bottom, then left-to-right)
    local numColumns = 3
    local totalItems = #standardFocalLengths
    local itemsPerColumn = math.ceil(totalItems / numColumns)

    local columns = {}
    for c = 1, numColumns do
      columns[c] = {}
    end

    local availableIndex = 0
    for i, fl in ipairs(standardFocalLengths) do
      local isAvailable = fl > originalFL

      local colorName, colorLr
      if isAvailable then
        availableIndex = availableIndex + 1
        local colorIndex = ((availableIndex - 1) % #colorNames) + 1
        colorName = colorNames[colorIndex]
        colorLr = legendColors[colorName]
      end

      local colIndex = math.floor((i - 1) / itemsPerColumn) + 1
      if colIndex > numColumns then colIndex = numColumns end

      table.insert(columns[colIndex], f:row {
        f:checkbox {
          value = LrView.bind("show_" .. fl),
          title = string.format("%dmm", fl),
          width = 70,
          enabled = LrView.bind("enabled_" .. fl),
        },
        f:static_text {
          title = isAvailable and "■" or "",
          text_color = colorLr or LrColor(0.5, 0.5, 0.5),
          font = "<system/bold>",
          width = 12,
          visible = isAvailable and LrView.bind("show_" .. fl) or false,
        },
      })
    end

    -- Wrap each column's items in f:column, then lay them out in a row
    local columnViews = {}
    for c = 1, numColumns do
      table.insert(columnViews, f:column(columns[c]))
      if c < numColumns then
        table.insert(columnViews, f:spacer { width = 20 })
      end
    end
    local checkboxRows = { f:row(columnViews) }

    -- Build image view: unified renderer (macOS JXA / Windows PowerShell, with legacy fallback)
    local imageView = FOVRenderer.createUnifiedImageView(
      photo, allCropRects, croppedCropRects, props,
      displayWidth, displayHeight, imageWidth, imageHeight,
      croppedDisplayWidth, croppedDisplayHeight, croppedWidth, croppedHeight,
      standardFocalLengths, cropRect, subjectDistance
    )

    local contents = f:column {
      bind_to_object = props,
      spacing = f:control_spacing(),

      -- Header
      f:row {
        f:static_text {
          title = LrView.bind("headerText"),
          font = "<system/bold>",
        },
      },

      f:spacer { height = 5 },

      -- Focal length checkboxes
      f:group_box {
        title = "Target Focal Lengths (select to show overlay)",
        fill_horizontal = 1,
        f:column(checkboxRows),
      },

      -- Highlight crop and view mode dropdowns
      f:row {
        f:static_text {
          title = "View:",
          alignment = "right",
          width = 35,
        },
        f:popup_menu {
          value = LrView.bind("viewMode"),
          items = LrView.bind("viewModeItems"),
          width = 110,
          enabled = isCropped,
        },
        f:spacer { width = 15 },
        f:static_text {
          title = "Highlight crop:",
          alignment = "right",
          width = 90,
        },
        f:popup_menu {
          value = LrView.bind("highlightFL"),
          items = LrView.bind("highlightFLItems"),
          width = 120,
        },
        f:spacer { width = 15 },
        f:checkbox {
          title = "Show distance",
          value = LrView.bind("showDistance"),
          visible = subjectDistance ~= nil,
        },
        f:static_text {
          title = LrView.bind("renderWarning"),
          text_color = LrColor(0.8, 0.5, 0),
          font = "<system/small>",
          visible = LrView.bind {
            key = "renderWarning",
            transform = function(value) return value ~= nil and value ~= "" end,
          },
        },
      },

      f:spacer { height = 10 },

      -- Image with overlays
      f:row {
        f:view {
          width = displayWidth,
          height = displayHeight,
          imageView,
        },
      },
    }

    -- Show the dialog
    LrDialogs.presentModalDialog {
      title = "FOV Overlay Guide",
      contents = contents,
      actionVerb = "Close",
      cancelVerb = "< exclude >",
      resizable = true,
    }

  end)
end)
