--[[
  FOVRenderer.lua

  Handles rendering of FOV overlay rectangles on the image display.
  Uses PNG corner markers positioned at rectangle corners.
--]]

local LrView = import 'LrView'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrTasks = import 'LrTasks'

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

-- ============================================================
-- Windows rendering: PowerShell + System.Drawing
-- On Windows, place="overlapping" with PNG overlays is unreliable.
-- Instead, export the photo as JPEG and draw corners directly onto it.
-- ============================================================

-- RGB values matching the PNG asset colors
FOVRenderer.colorRGB = {
  green   = {0, 200, 0},
  yellow  = {255, 200, 0},
  orange  = {255, 128, 0},
  red     = {255, 50, 50},
  cyan    = {0, 200, 220},
  magenta = {220, 0, 220},
  blue    = {80, 120, 255},
  lime    = {160, 255, 0},
  pink    = {255, 120, 180},
  white   = {240, 240, 240},
}

--[[
  Export the photo as a JPEG thumbnail to a temp file.
  Uses requestJpegThumbnail which returns the photo as displayed (with crop).
  Pattern follows Focus Points MogrifyUtils.exportToDisk.
]]
function FOVRenderer.exportBaseImage(photo, displayWidth, displayHeight)
  local tempPath = LrPathUtils.getStandardFilePath("temp")
  local basePath = LrPathUtils.child(tempPath, "fov_base.jpg")

  if LrFileUtils.exists(basePath) then
    LrFileUtils.delete(basePath)
  end

  local done = false
  photo:requestJpegThumbnail(displayWidth, displayHeight, function(data, errorMsg)
    if data then
      local success, _ = pcall(function()
        local localFile = io.open(basePath, "w+b")
        if localFile then
          localFile:write(data)
          localFile:close()
        end
      end)
    end
    done = true
  end)

  -- Busy wait for async callback (same pattern as Focus Points)
  while not done do LrTasks.sleep(0.2) end

  return basePath
end

--[[
  Render overlay image using PowerShell + System.Drawing.
  Draws corner brackets onto the base JPEG for each enabled focal length.

  Parameters:
    baseImagePath: Path to the base JPEG
    allCropRects: All crop rectangles (from calculateAllCropRects)
    enabledFLs: Array of focal lengths currently checked
    displayWidth/Height: Display dimensions
    workingWidth/Height: Image pixel dimensions (for scaling)
    renderCount: Counter for unique output filenames

  Returns: Path to the rendered JPEG
]]
function FOVRenderer.renderWindowsOverlay(baseImagePath, allCropRects, enabledFLs, displayWidth, displayHeight, workingWidth, workingHeight, renderCount)
  local tempPath = LrPathUtils.getStandardFilePath("temp")
  local outputPath = LrPathUtils.child(tempPath, "fov_render_" .. renderCount .. ".jpg")
  local scriptPath = LrPathUtils.child(tempPath, "fov_draw.ps1")

  -- Delete previous render if exists
  if LrFileUtils.exists(outputPath) then
    LrFileUtils.delete(outputPath)
  end

  local lines = {}
  table.insert(lines, 'Add-Type -AssemblyName System.Drawing')
  table.insert(lines, '$img = [System.Drawing.Image]::FromFile("' .. baseImagePath .. '")')
  table.insert(lines, '$g = [System.Drawing.Graphics]::FromImage($img)')

  -- Compute scale from actual JPEG dimensions to working (sensor) dimensions.
  -- This handles Windows display scaling (125%, 150%, etc.) where the JPEG
  -- returned by requestJpegThumbnail may differ from the requested size.
  table.insert(lines, '$scaleX = $img.Width / ' .. workingWidth)
  table.insert(lines, '$scaleY = $img.Height / ' .. workingHeight)
  table.insert(lines, string.format('$cl = [math]::Max(15, [math]::Floor(40 * $img.Width / %d))', displayWidth))
  table.insert(lines, string.format('$pw = [math]::Max(2, [math]::Floor(4 * $img.Width / %d))', displayWidth))

  for i, rect in ipairs(allCropRects) do
    -- Check if this focal length is in the enabled list
    local isEnabled = false
    for _, fl in ipairs(enabledFLs) do
      if fl == rect.focalLength then
        isEnabled = true
        break
      end
    end

    if isEnabled then
      local colorIndex = ((i - 1) % #FOVRenderer.colorNames) + 1
      local colorName = FOVRenderer.colorNames[colorIndex]
      local rgb = FOVRenderer.colorRGB[colorName]

      table.insert(lines, string.format(
        '$p = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, %d, %d, %d), $pw)',
        rgb[1], rgb[2], rgb[3]))

      -- Pass raw rect coordinates; PowerShell scales using actual image dimensions
      table.insert(lines, string.format('$left = [math]::Floor(%d * $scaleX)', rect.left))
      table.insert(lines, string.format('$top = [math]::Floor(%d * $scaleY)', rect.top))
      table.insert(lines, string.format('$right = [math]::Floor(%d * $scaleX)', rect.left + rect.width))
      table.insert(lines, string.format('$bottom = [math]::Floor(%d * $scaleY)', rect.top + rect.height))

      -- Top-left corner
      table.insert(lines, '$g.DrawLine($p, $left, $top, ($left + $cl), $top)')
      table.insert(lines, '$g.DrawLine($p, $left, $top, $left, ($top + $cl))')
      -- Top-right corner
      table.insert(lines, '$g.DrawLine($p, ($right - $cl), $top, $right, $top)')
      table.insert(lines, '$g.DrawLine($p, $right, $top, $right, ($top + $cl))')
      -- Bottom-left corner
      table.insert(lines, '$g.DrawLine($p, $left, $bottom, ($left + $cl), $bottom)')
      table.insert(lines, '$g.DrawLine($p, $left, ($bottom - $cl), $left, $bottom)')
      -- Bottom-right corner
      table.insert(lines, '$g.DrawLine($p, ($right - $cl), $bottom, $right, $bottom)')
      table.insert(lines, '$g.DrawLine($p, $right, ($bottom - $cl), $right, $bottom)')

      table.insert(lines, '$p.Dispose()')
    end
  end

  table.insert(lines, '$g.Dispose()')
  table.insert(lines, '$img.Save("' .. outputPath .. '", [System.Drawing.Imaging.ImageFormat]::Jpeg)')
  table.insert(lines, '$img.Dispose()')

  local scriptFile = io.open(scriptPath, "w+b")
  scriptFile:write(table.concat(lines, "\r\n"))
  scriptFile:close()

  -- Double-quote wrapping matches Focus Points LrTasks.execute pattern
  local cmdline = 'powershell -ExecutionPolicy Bypass -File "' .. scriptPath .. '"'
  LrTasks.execute('"' .. cmdline .. '"')

  -- Yield to avoid Windows process queue saturation (Focus Points pattern)
  LrTasks.sleep(0.02)
  LrTasks.yield()

  return outputPath
end

--[[
  Create the Windows image view with observer-based re-rendering.
  Exports the photo, renders overlays via PowerShell, and sets up
  property observers to re-render when checkboxes change.

  Parameters:
    photo: LrPhoto object
    allCropRects: All crop rectangles
    props: Observable property table
    displayWidth/Height: Display dimensions
    workingWidth/Height: Image pixel dimensions
    focalLengths: Array of all standard focal lengths (for observers)

  Returns: LrView element (f:picture bound to rendered image path)
]]
function FOVRenderer.createWindowsImageView(photo, allCropRects, props, displayWidth, displayHeight, workingWidth, workingHeight, focalLengths)
  local f = LrView.osFactory()

  -- Export the base photo as JPEG
  local baseImagePath = FOVRenderer.exportBaseImage(photo, displayWidth, displayHeight)

  local renderCount = { value = 0 }

  local function getEnabledFLs()
    local enabled = {}
    for _, fl in ipairs(focalLengths) do
      if props["show_" .. fl] then
        table.insert(enabled, fl)
      end
    end
    return enabled
  end

  local function rerender()
    renderCount.value = renderCount.value + 1
    local enabledFLs = getEnabledFLs()
    local outputPath = FOVRenderer.renderWindowsOverlay(
      baseImagePath, allCropRects, enabledFLs,
      displayWidth, displayHeight, workingWidth, workingHeight,
      renderCount.value
    )
    props.overlayImagePath = outputPath
  end

  -- Initial render
  rerender()

  -- Observe checkbox changes to re-render
  for _, fl in ipairs(focalLengths) do
    props:addObserver("show_" .. fl, function()
      LrTasks.startAsyncTask(function()
        rerender()
      end)
    end)
  end

  return f:picture {
    value = LrView.bind("overlayImagePath"),
    width = displayWidth,
    height = displayHeight,
  }
end

return FOVRenderer
