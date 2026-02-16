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

local FOVCalculator = require 'FOVCalculator'
local FOVRenderer = require 'FOVRenderer'

-- Standard focal lengths in photography
local standardFocalLengths = {
  24, 28, 35, 50, 70, 85, 100, 135, 200, 300, 400, 420, 450, 500, 560, 600, 800, 840, 1000, 1200
}

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

    local originalFL = FOVCalculator.parseFocalLength(focalLengthStr)
    local imageWidth, imageHeight = FOVCalculator.parseDimensions(dimensionsStr)

    if not originalFL then
      LrDialogs.message("FOV Overlay", "Could not read focal length from photo metadata.\n\nFocal Length: " .. tostring(focalLengthStr), "warning")
      return
    end

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

    -- Working dimensions and effective FL account for any crop
    local workingWidth, workingHeight, effectiveFL
    if isCropped then
      workingWidth = math.floor(imageWidth * (cropRight - cropLeft))
      workingHeight = math.floor(imageHeight * (cropBottom - cropTop))
      effectiveFL = math.floor(originalFL / (cropRight - cropLeft) + 0.5)
    else
      workingWidth = imageWidth
      workingHeight = imageHeight
      effectiveFL = originalFL
    end

    -- Create observable properties
    local props = LrBinding.makePropertyTable(context)

    -- Initialize checkbox states: enabled for the first 4 available FLs, disabled for those <= effectiveFL
    local enabledCount = 0
    for _, fl in ipairs(standardFocalLengths) do
      if fl > effectiveFL then
        enabledCount = enabledCount + 1
        props["show_" .. fl] = (enabledCount <= 4)
      else
        props["show_" .. fl] = false
      end
    end

    -- Derive max display size from LR application window
    local appWidth, appHeight = LrSystemInfo.appWindowSize()
    local maxDisplayWidth = math.floor(appWidth * 0.7)
    local maxDisplayHeight = math.floor(appHeight * 0.6)

    local aspectRatio = workingWidth / workingHeight

    local displayWidth, displayHeight
    if aspectRatio > (maxDisplayWidth / maxDisplayHeight) then
      displayWidth = maxDisplayWidth
      displayHeight = math.floor(maxDisplayWidth / aspectRatio)
    else
      displayHeight = maxDisplayHeight
      displayWidth = math.floor(maxDisplayHeight * aspectRatio)
    end

    -- Calculate crop rects for focal lengths greater than effective FL
    local allCropRects = FOVCalculator.calculateAllCropRects(effectiveFL, standardFocalLengths, workingWidth, workingHeight)

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

    local availableIndex = 0
    for i, fl in ipairs(standardFocalLengths) do
      local isAvailable = fl > effectiveFL

      -- Calculate crop info and assign color (only for available FLs)
      local rect, colorName, colorLr
      if isAvailable then
        availableIndex = availableIndex + 1
        local colorIndex = ((availableIndex - 1) % #colorNames) + 1
        colorName = colorNames[colorIndex]
        colorLr = legendColors[colorName]
        rect = FOVCalculator.calculateCropRect(effectiveFL, fl, workingWidth, workingHeight)
      end
      local mpText = rect and string.format("%.1fMP", rect.megapixels) or ""

      table.insert(currentRow, f:row {
        f:checkbox {
          value = LrView.bind("show_" .. fl),
          title = string.format("%dmm", fl),
          width = 70,
          enabled = isAvailable,
        },
        f:static_text {
          title = isAvailable and "■" or "",
          text_color = colorLr or LrColor(0.5, 0.5, 0.5),
          font = "<system/bold>",
          width = 12,
          visible = isAvailable and LrView.bind("show_" .. fl) or false,
        },
        f:static_text {
          title = mpText,
          width = 45,
          font = "<system/small>",
          text_color = LrColor(0.5, 0.5, 0.5),
        },
      })

      -- Start new row after 4 items
      if #currentRow >= 4 or i == #standardFocalLengths then
        table.insert(checkboxRows, f:row(currentRow))
        currentRow = {}
      end
    end

    -- Build image view with all overlays (visibility bound to checkbox props)
    local imageView = FOVRenderer.createImageWithBindableOverlays(
      photo, allCropRects, props, displayWidth, displayHeight, workingWidth, workingHeight
    )

    local contents = f:column {
      bind_to_object = props,
      spacing = f:control_spacing(),

      -- Header
      f:row {
        f:static_text {
          title = isCropped
            and string.format("Shot at %dmm  |  Cropped to %dmm equiv  |  %d × %d  |  %.1f MP",
              originalFL, effectiveFL, workingWidth, workingHeight, (workingWidth * workingHeight) / 1000000)
            or string.format("Original: %dmm  |  %d × %d  |  %.1f MP",
              originalFL, imageWidth, imageHeight, (imageWidth * imageHeight) / 1000000),
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
    }

  end)
end)
