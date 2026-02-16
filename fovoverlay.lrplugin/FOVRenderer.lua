--[[
  FOVRenderer.lua

  Handles rendering of FOV overlay rectangles on the image display.
  Uses PNG corner markers positioned at rectangle corners.
--]]

local LrView = import 'LrView'
local LrPathUtils = import 'LrPathUtils'

local FOVRenderer = {}

-- Corner asset size (must match the PNG files)
FOVRenderer.cornerSize = 40

-- Color names for different crop levels (index by position)
FOVRenderer.colorNames = { "green", "yellow", "orange", "red", "cyan", "magenta", "blue", "lime", "pink", "white" }

--[[
  Get the path to a corner asset file
--]]
function FOVRenderer.getCornerAsset(corner, colorName)
  local pluginPath = _PLUGIN.path
  local assetPath = LrPathUtils.child(pluginPath, "assets")
  local fileName = string.format("corner_%s_%s.png", corner, colorName)
  return LrPathUtils.child(assetPath, fileName)
end

--[[
  Create corner overlay views for a single rectangle

  Parameters:
    rect: Crop rectangle from FOVCalculator
    displayWidth: Width of the display area
    displayHeight: Height of the display area
    imageWidth: Original image width
    imageHeight: Original image height
    colorName: Color name (green, yellow, orange, red)

  Returns: Table of LrView elements for the four corners
--]]
function FOVRenderer.createCornerOverlays(rect, displayWidth, displayHeight, imageWidth, imageHeight, colorName)
  local f = LrView.osFactory()
  local corners = {}

  -- Calculate scale factors
  local scaleX = displayWidth / imageWidth
  local scaleY = displayHeight / imageHeight

  -- Scale the rectangle coordinates
  local left = rect.left * scaleX
  local top = rect.top * scaleY
  local right = (rect.left + rect.width) * scaleX
  local bottom = (rect.top + rect.height) * scaleY

  local cs = FOVRenderer.cornerSize

  -- Top-left corner
  table.insert(corners, f:view {
    f:picture {
      value = FOVRenderer.getCornerAsset("tl", colorName),
    },
    margin_left = left,
    margin_top = top,
  })

  -- Top-right corner
  table.insert(corners, f:view {
    f:picture {
      value = FOVRenderer.getCornerAsset("tr", colorName),
    },
    margin_left = right - cs,
    margin_top = top,
  })

  -- Bottom-left corner
  table.insert(corners, f:view {
    f:picture {
      value = FOVRenderer.getCornerAsset("bl", colorName),
    },
    margin_left = left,
    margin_top = bottom - cs,
  })

  -- Bottom-right corner
  table.insert(corners, f:view {
    f:picture {
      value = FOVRenderer.getCornerAsset("br", colorName),
    },
    margin_left = right - cs,
    margin_top = bottom - cs,
  })

  return corners
end

--[[
  Create all overlay views for multiple crop rectangles

  Parameters:
    cropRects: Array of crop rectangles from FOVCalculator
    displayWidth: Width of the display area
    displayHeight: Height of the display area
    imageWidth: Original image width
    imageHeight: Original image height

  Returns: LrView with all overlays
--]]
function FOVRenderer.createAllOverlays(cropRects, displayWidth, displayHeight, imageWidth, imageHeight)
  local f = LrView.osFactory()
  local viewsTable = { place = "overlapping" }

  for i, rect in ipairs(cropRects) do
    local colorIndex = ((i - 1) % #FOVRenderer.colorNames) + 1
    local colorName = FOVRenderer.colorNames[colorIndex]

    local corners = FOVRenderer.createCornerOverlays(
      rect,
      displayWidth,
      displayHeight,
      imageWidth,
      imageHeight,
      colorName
    )

    for _, corner in ipairs(corners) do
      table.insert(viewsTable, corner)
    end
  end

  return f:view(viewsTable)
end

--[[
  Create the complete image view with all overlays

  Parameters:
    photo: LrPhoto object
    cropRects: Array of crop rectangles
    displayWidth: Desired display width
    displayHeight: Desired display height
    imageWidth: Original image width
    imageHeight: Original image height

  Returns: LrView element with image and overlays
--]]
function FOVRenderer.createImageWithOverlays(photo, cropRects, displayWidth, displayHeight, imageWidth, imageHeight)
  local f = LrView.osFactory()

  -- Create the base image view
  local imageView = f:catalog_photo {
    photo = photo,
    width = displayWidth,
    height = displayHeight,
  }

  -- Create all overlay corners
  local overlays = FOVRenderer.createAllOverlays(
    cropRects,
    displayWidth,
    displayHeight,
    imageWidth,
    imageHeight
  )

  -- Combine image and overlays
  return f:view {
    imageView,
    overlays,
    place = 'overlapping',
  }
end

--[[
  Create the complete image view with overlays whose visibility is bound
  to observable properties, enabling live toggling via checkboxes.

  Parameters:
    photo: LrPhoto object
    allCropRects: Array of ALL crop rectangles (for every available focal length)
    props: Observable property table with "show_<fl>" keys
    displayWidth: Desired display width
    displayHeight: Desired display height
    imageWidth: Original image width
    imageHeight: Original image height

  Returns: LrView element with image and bindable overlays
--]]
function FOVRenderer.createImageWithBindableOverlays(photo, allCropRects, props, displayWidth, displayHeight, imageWidth, imageHeight)
  local f = LrView.osFactory()

  -- Create the base image view
  local imageView = f:catalog_photo {
    photo = photo,
    width = displayWidth,
    height = displayHeight,
  }

  -- Build overlay views for each focal length, each with bound visibility
  local overlayViews = {}
  for i, rect in ipairs(allCropRects) do
    local colorIndex = ((i - 1) % #FOVRenderer.colorNames) + 1
    local colorName = FOVRenderer.colorNames[colorIndex]

    local corners = FOVRenderer.createCornerOverlays(
      rect, displayWidth, displayHeight, imageWidth, imageHeight, colorName
    )

    -- Wrap this focal length's corners in a view bound to its checkbox property
    local cornerGroup = { place = "overlapping" }
    for _, corner in ipairs(corners) do
      table.insert(cornerGroup, corner)
    end

    table.insert(overlayViews, f:view {
      bind_to_object = props,
      visible = LrView.bind("show_" .. rect.focalLength),
      f:view(cornerGroup),
    })
  end

  -- Combine image and all overlay groups
  local combined = { place = 'overlapping' }
  table.insert(combined, imageView)
  for _, ov in ipairs(overlayViews) do
    table.insert(combined, ov)
  end

  return f:view(combined)
end

return FOVRenderer
