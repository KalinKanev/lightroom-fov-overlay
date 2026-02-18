--[[
  FOVRenderer.lua

  Handles rendering of FOV overlay rectangles on the image display.
  Uses full rectangle outlines rendered onto an exported JPEG.
  macOS: JXA + NSImage. Windows: PowerShell + System.Drawing.
  Fallback: PNG corner markers (legacy).
--]]

local LrView = import 'LrView'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrTasks = import 'LrTasks'

local FOVRenderer = {}

-- RAW file extensions that may contain an embedded JPEG preview
FOVRenderer.rawExtensions = {
  arw = true, cr2 = true, cr3 = true, nef = true, nrw = true,
  raf = true, orf = true, rw2 = true, pef = true, dng = true,
  srw = true, x3f = true, iiq = true, ["3fr"] = true, rwl = true,
}

-- Corner asset size (must match the PNG files)
FOVRenderer.cornerSize = 40

-- Color names for different crop levels (index by position)
FOVRenderer.colorNames = { "green", "yellow", "orange", "red", "cyan", "magenta", "blue", "lime", "pink", "white" }

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
  Get the path to a corner asset file
--]]
function FOVRenderer.getCornerAsset(corner, colorName)
  local pluginPath = _PLUGIN.path
  local assetPath = LrPathUtils.child(pluginPath, "assets")
  local fileName = string.format("corner_%s_%s.png", corner, colorName)
  return LrPathUtils.child(assetPath, fileName)
end

-- ============================================================
-- Legacy corner overlay functions (fallback for macOS if JXA fails)
-- ============================================================

--[[
  Create corner overlay views for a single rectangle (legacy fallback)
--]]
function FOVRenderer.createCornerOverlays(rect, displayWidth, displayHeight, imageWidth, imageHeight, colorName)
  local f = LrView.osFactory()
  local corners = {}

  local scaleX = displayWidth / imageWidth
  local scaleY = displayHeight / imageHeight

  local left = rect.left * scaleX
  local top = rect.top * scaleY
  local right = (rect.left + rect.width) * scaleX
  local bottom = (rect.top + rect.height) * scaleY

  local cs = FOVRenderer.cornerSize

  table.insert(corners, f:view {
    f:picture { value = FOVRenderer.getCornerAsset("tl", colorName) },
    margin_left = left, margin_top = top,
  })
  table.insert(corners, f:view {
    f:picture { value = FOVRenderer.getCornerAsset("tr", colorName) },
    margin_left = right - cs, margin_top = top,
  })
  table.insert(corners, f:view {
    f:picture { value = FOVRenderer.getCornerAsset("bl", colorName) },
    margin_left = left, margin_top = bottom - cs,
  })
  table.insert(corners, f:view {
    f:picture { value = FOVRenderer.getCornerAsset("br", colorName) },
    margin_left = right - cs, margin_top = bottom - cs,
  })

  return corners
end

--[[
  Create legacy image view with bindable corner overlays (macOS fallback).
  No dimming support in this mode.
--]]
function FOVRenderer.createLegacyImageView(photo, allCropRects, props, displayWidth, displayHeight, imageWidth, imageHeight)
  local f = LrView.osFactory()

  local imageView = f:catalog_photo {
    photo = photo,
    width = displayWidth,
    height = displayHeight,
  }

  local overlayViews = {}
  for i, rect in ipairs(allCropRects) do
    local colorIndex = rect.colorIndex or (((i - 1) % #FOVRenderer.colorNames) + 1)
    local colorName = FOVRenderer.colorNames[colorIndex]

    local corners = FOVRenderer.createCornerOverlays(
      rect, displayWidth, displayHeight, imageWidth, imageHeight, colorName
    )

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

  local combined = { place = 'overlapping' }
  table.insert(combined, imageView)
  for _, ov in ipairs(overlayViews) do
    table.insert(combined, ov)
  end

  return f:view(combined)
end

-- ============================================================
-- Base image export
-- ============================================================

--[[
  Export the photo as a JPEG thumbnail to a temp file.
  Uses requestJpegThumbnail which returns the photo as displayed (with crop).
--]]
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

  while not done do LrTasks.sleep(0.2) end

  return basePath
end

-- ============================================================
-- Uncropped image export (Option D: ExifTool for RAW, original for JPEG)
-- ============================================================

--[[
  Locate the bundled ExifTool binary.
  Returns the path string, or nil if not found.
--]]
function FOVRenderer.findExifTool()
  local binPath = LrPathUtils.child(_PLUGIN.path, "bin")
  if WIN_ENV then
    local exePath = LrPathUtils.child(binPath, "exiftool.exe")
    if LrFileUtils.exists(exePath) then return exePath end
  else
    local macPath = LrPathUtils.child(binPath, "exiftool")
    macPath = LrPathUtils.child(macPath, "exiftool")
    if LrFileUtils.exists(macPath) then return macPath end
  end
  return nil
end

--[[
  Extract the embedded JPEG preview from a RAW file using ExifTool.
  Tries JpgFromRaw first, then PreviewImage as fallback.
  Returns the path to the extracted JPEG, or nil on failure.
--]]
function FOVRenderer.extractRawPreview(exiftoolPath, rawFilePath)
  local tempPath = LrPathUtils.getStandardFilePath("temp")
  local outputPath = LrPathUtils.child(tempPath, "fov_uncropped.jpg")

  if LrFileUtils.exists(outputPath) then
    LrFileUtils.delete(outputPath)
  end

  local singleQuoteWrap = '\'"\'"\''

  -- Try JpgFromRaw first (usually full-size)
  local tags = { "JpgFromRaw", "PreviewImage" }
  for _, tag in ipairs(tags) do
    local cmd
    if WIN_ENV then
      cmd = string.format('"""%s" -b -%s "%s" > "%s"""',
        exiftoolPath, tag, rawFilePath, outputPath)
    else
      local et = exiftoolPath:gsub("'", singleQuoteWrap)
      local rf = rawFilePath:gsub("'", singleQuoteWrap)
      cmd = string.format("'%s' -b -%s '%s' > '%s'",
        et, tag, rf, outputPath)
    end

    local rc = LrTasks.execute(cmd)

    if WIN_ENV then
      LrTasks.sleep(0.02)
      LrTasks.yield()
    end

    -- Check if extraction produced a valid file (> 1KB to filter out tiny thumbnails)
    if rc == 0 and LrFileUtils.exists(outputPath) then
      local fileAttrs = LrFileUtils.fileAttributes(outputPath)
      if fileAttrs and fileAttrs.fileSize and fileAttrs.fileSize > 1024 then
        return outputPath
      end
    end

    -- Clean up failed attempt before trying next tag
    if LrFileUtils.exists(outputPath) then
      LrFileUtils.delete(outputPath)
    end
  end

  return nil
end

--[[
  Get the full uncropped base image for display.

  For RAW files: extracts the embedded JPEG preview via ExifTool.
  For JPEG files: uses the original file directly.
  For other formats: falls back to requestJpegThumbnail (cropped).

  Parameters:
    photo: LrPhoto object
    displayWidth/Height: Desired display dimensions (used for fallback)

  Returns table:
    { path = <string>, isUncropped = <boolean> }
--]]
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
    if exiftoolPath then
      local previewPath = FOVRenderer.extractRawPreview(exiftoolPath, originalPath)
      if previewPath then
        return { path = previewPath, isUncropped = true }
      end
    end
  end

  -- Fallback: use requestJpegThumbnail (returns cropped image)
  local croppedPath = FOVRenderer.exportBaseImage(photo, displayWidth, displayHeight)
  return { path = croppedPath, isUncropped = false }
end

-- ============================================================
-- macOS rendering: JXA + NSImage
-- ============================================================

--[[
  Render overlay image using JXA (JavaScript for Automation) + Cocoa.
  Draws full rectangle outlines, optional crop overlay, and optional dimming.

  Parameters:
    baseImagePath: Path to the base JPEG
    allCropRects: All crop rectangles
    enabledFLs: Array of focal lengths currently checked
    displayWidth/Height: Display dimensions
    workingWidth/Height: Image pixel dimensions (for scaling)
    renderCount: Counter for unique output filenames
    highlightFL: Focal length to highlight (0 = none)
    cropRect: Normalized crop rect {left,top,right,bottom} or nil

  Returns: Path to the rendered JPEG
--]]
function FOVRenderer.renderMacOverlay(baseImagePath, allCropRects, enabledFLs, displayWidth, displayHeight, workingWidth, workingHeight, renderCount, highlightFL, cropRect)
  local tempPath = LrPathUtils.getStandardFilePath("temp")
  local outputPath = LrPathUtils.child(tempPath, "fov_render_" .. renderCount .. ".jpg")
  local scriptPath = LrPathUtils.child(tempPath, "fov_draw.js")

  if LrFileUtils.exists(outputPath) then
    LrFileUtils.delete(outputPath)
  end

  local lines = {}
  table.insert(lines, "ObjC.import('Cocoa')")
  table.insert(lines, string.format("var basePath = '%s'", baseImagePath:gsub("'", "\\'")))
  table.insert(lines, string.format("var outputPath = '%s'", outputPath:gsub("'", "\\'")))
  table.insert(lines, "var srcImg = $.NSImage.alloc.initWithContentsOfFile(basePath)")
  -- Resize to display dimensions to avoid Retina 2x scaling issues
  table.insert(lines, string.format("var targetW = %d", displayWidth))
  table.insert(lines, string.format("var targetH = %d", displayHeight))
  table.insert(lines, "var img = $.NSImage.alloc.initWithSize($.NSMakeSize(targetW, targetH))")
  table.insert(lines, "img.lockFocus")
  table.insert(lines, "srcImg.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, targetW, targetH), $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0)")
  table.insert(lines, "img.unlockFocus")
  -- Now work on the resized image
  table.insert(lines, "var imgW = targetW")
  table.insert(lines, "var imgH = targetH")
  table.insert(lines, string.format("var scaleX = imgW / %d", workingWidth))
  table.insert(lines, string.format("var scaleY = imgH / %d", workingHeight))
  -- Pen width proportional to image size
  table.insert(lines, string.format("var pw = Math.max(2, Math.floor(4 * imgW / %d))", displayWidth))
  table.insert(lines, "img.lockFocus")

  -- Draw crop overlay (darken area outside the LR crop polygon)
  if cropRect then
    local c = cropRect.corners
    -- Scale normalized corners to pixel coords, flip Y for NSImage (origin bottom-left)
    for i = 1, 4 do
      table.insert(lines, string.format("var cx%d = Math.floor(%s * imgW)", i, c[i][1]))
      table.insert(lines, string.format("var cy%d = imgH - Math.floor(%s * imgH)", i, c[i][2]))
    end

    -- Build crop polygon path
    table.insert(lines, "var cropPoly = $.NSBezierPath.bezierPath")
    table.insert(lines, "cropPoly.moveToPoint($.NSMakePoint(cx1, cy1))")
    table.insert(lines, "cropPoly.lineToPoint($.NSMakePoint(cx2, cy2))")
    table.insert(lines, "cropPoly.lineToPoint($.NSMakePoint(cx3, cy3))")
    table.insert(lines, "cropPoly.lineToPoint($.NSMakePoint(cx4, cy4))")
    table.insert(lines, "cropPoly.closePath")

    -- Dimming: even-odd fill — full image rect with crop polygon hole
    table.insert(lines, "var dimPath = $.NSBezierPath.bezierPathWithRect($.NSMakeRect(0, 0, imgW, imgH))")
    table.insert(lines, "dimPath.appendBezierPath(cropPoly)")
    table.insert(lines, "dimPath.setWindingRule(1)")  -- NSEvenOddWindingRule
    table.insert(lines, "var cropDim = $.NSColor.colorWithCalibratedRedGreenBlueAlpha(0, 0, 0, 0.5)")
    table.insert(lines, "cropDim.set")
    table.insert(lines, "dimPath.fill")

    -- Draw crop border (white line)
    table.insert(lines, "var cropBorder = $.NSColor.colorWithCalibratedRedGreenBlueAlpha(1, 1, 1, 0.7)")
    table.insert(lines, "cropBorder.set")
    table.insert(lines, "cropPoly.setLineWidth(Math.max(1, pw / 2))")
    table.insert(lines, "cropPoly.stroke")
  end

  -- Draw full rectangles for each enabled FL
  for i, rect in ipairs(allCropRects) do
    local isEnabled = false
    for _, fl in ipairs(enabledFLs) do
      if fl == rect.focalLength then
        isEnabled = true
        break
      end
    end

    if isEnabled then
      local colorIndex = rect.colorIndex or (((i - 1) % #FOVRenderer.colorNames) + 1)
      local colorName = FOVRenderer.colorNames[colorIndex]
      local rgb = FOVRenderer.colorRGB[colorName]

      -- NSImage coordinate system is flipped (origin bottom-left), so invert Y
      table.insert(lines, string.format(
        "var color%d = $.NSColor.colorWithCalibratedRedGreenBlueAlpha(%s, %s, %s, 0.5)",
        i, rgb[1] / 255, rgb[2] / 255, rgb[3] / 255))
      table.insert(lines, string.format("color%d.set", i))

      table.insert(lines, string.format("var left%d = Math.floor(%d * scaleX)", i, rect.left))
      table.insert(lines, string.format("var top%d = Math.floor(%d * scaleY)", i, rect.top))
      table.insert(lines, string.format("var rw%d = Math.floor(%d * scaleX)", i, rect.width))
      table.insert(lines, string.format("var rh%d = Math.floor(%d * scaleY)", i, rect.height))
      -- Flip Y: NSImage origin is bottom-left
      table.insert(lines, string.format("var ny%d = imgH - top%d - rh%d", i, i, i))

      table.insert(lines, string.format(
        "var path%d = $.NSBezierPath.bezierPathWithRect($.NSMakeRect(left%d, ny%d, rw%d, rh%d))",
        i, i, i, i, i))
      table.insert(lines, string.format("path%d.setLineWidth(pw)", i))
      table.insert(lines, string.format("path%d.stroke", i))
    end
  end

  -- Dimming: fill 4 strips around the highlight rect
  if highlightFL and highlightFL > 0 then
    local hlRect = nil
    for _, rect in ipairs(allCropRects) do
      if rect.focalLength == highlightFL then
        hlRect = rect
        break
      end
    end

    if hlRect then
      table.insert(lines, "var dim = $.NSColor.colorWithCalibratedRedGreenBlueAlpha(0, 0, 0, 0.45)")
      table.insert(lines, "dim.set")

      table.insert(lines, string.format("var hlLeft = Math.floor(%d * scaleX)", hlRect.left))
      table.insert(lines, string.format("var hlTop = Math.floor(%d * scaleY)", hlRect.top))
      table.insert(lines, string.format("var hlRight = Math.floor(%d * scaleX)", hlRect.left + hlRect.width))
      table.insert(lines, string.format("var hlBottom = Math.floor(%d * scaleY)", hlRect.top + hlRect.height))
      -- Flip Y for NSImage coordinates
      table.insert(lines, "var hlNTop = imgH - hlTop")        -- flipped top (higher in image coords)
      table.insert(lines, "var hlNBottom = imgH - hlBottom")   -- flipped bottom (lower in image coords)
      table.insert(lines, "var hlW = hlRight - hlLeft")
      table.insert(lines, "var hlH = hlNTop - hlNBottom")

      -- Top strip (above the highlight rect in visual space = above hlNTop in NSImage coords)
      table.insert(lines, "$.NSBezierPath.fillRect($.NSMakeRect(0, hlNTop, imgW, imgH - hlNTop))")
      -- Bottom strip (below the highlight rect in visual space = below hlNBottom in NSImage coords)
      table.insert(lines, "$.NSBezierPath.fillRect($.NSMakeRect(0, 0, imgW, hlNBottom))")
      -- Left strip
      table.insert(lines, "$.NSBezierPath.fillRect($.NSMakeRect(0, hlNBottom, hlLeft, hlH))")
      -- Right strip
      table.insert(lines, "$.NSBezierPath.fillRect($.NSMakeRect(hlRight, hlNBottom, imgW - hlRight, hlH))")
    end
  end

  table.insert(lines, "img.unlockFocus")

  -- Save as JPEG
  table.insert(lines, "var tiff = img.TIFFRepresentation")
  table.insert(lines, "var rep = $.NSBitmapImageRep.imageRepWithData(tiff)")
  table.insert(lines, "var props = $.NSDictionary.dictionaryWithObjectForKey(")
  table.insert(lines, "  $.NSNumber.numberWithFloat(0.92),")
  table.insert(lines, "  $.NSString.stringWithString('NSImageCompressionFactor'))")
  table.insert(lines, "var jpeg = rep.representationUsingTypeProperties($.NSBitmapImageFileTypeJPEG, props)")
  table.insert(lines, "jpeg.writeToFileAtomically(outputPath, true)")

  local scriptFile = io.open(scriptPath, "w+b")
  scriptFile:write(table.concat(lines, "\n"))
  scriptFile:close()

  local cmdline = 'osascript -l JavaScript "' .. scriptPath .. '"'
  local exitCode = LrTasks.execute(cmdline)

  LrTasks.sleep(0.02)
  LrTasks.yield()

  -- Return output path if rendering succeeded, nil otherwise
  if LrFileUtils.exists(outputPath) then
    return outputPath
  else
    return nil
  end
end

-- ============================================================
-- Windows rendering: PowerShell + System.Drawing
-- ============================================================

--[[
  Render overlay image using PowerShell + System.Drawing.
  Draws full rectangle outlines, optional crop overlay, and optional dimming.

  Parameters:
    baseImagePath: Path to the base JPEG
    allCropRects: All crop rectangles
    enabledFLs: Array of focal lengths currently checked
    displayWidth/Height: Display dimensions
    workingWidth/Height: Image pixel dimensions (for scaling)
    renderCount: Counter for unique output filenames
    highlightFL: Focal length to highlight (0 = none)
    cropRect: Normalized crop rect {left,top,right,bottom} or nil

  Returns: Path to the rendered JPEG
--]]
function FOVRenderer.renderWindowsOverlay(baseImagePath, allCropRects, enabledFLs, displayWidth, displayHeight, workingWidth, workingHeight, renderCount, highlightFL, cropRect)
  local tempPath = LrPathUtils.getStandardFilePath("temp")
  local outputPath = LrPathUtils.child(tempPath, "fov_render_" .. renderCount .. ".jpg")
  local scriptPath = LrPathUtils.child(tempPath, "fov_draw.ps1")

  if LrFileUtils.exists(outputPath) then
    LrFileUtils.delete(outputPath)
  end

  local lines = {}
  table.insert(lines, 'Add-Type -AssemblyName System.Drawing')
  table.insert(lines, '$img = [System.Drawing.Image]::FromFile("' .. baseImagePath .. '")')
  table.insert(lines, '$g = [System.Drawing.Graphics]::FromImage($img)')

  table.insert(lines, '$scaleX = $img.Width / ' .. workingWidth)
  table.insert(lines, '$scaleY = $img.Height / ' .. workingHeight)
  table.insert(lines, string.format('$pw = [math]::Max(2, [math]::Floor(4 * $img.Width / %d))', displayWidth))

  -- Draw crop overlay (darken area outside the LR crop polygon)
  if cropRect then
    local c = cropRect.corners
    -- Scale normalized corners to pixel coords
    for i = 1, 4 do
      table.insert(lines, string.format('$cx%d = [math]::Floor(%s * $img.Width)', i, c[i][1]))
      table.insert(lines, string.format('$cy%d = [math]::Floor(%s * $img.Height)', i, c[i][2]))
    end

    -- Build crop polygon and even-odd path for dimming
    table.insert(lines, '$cropPoints = @(')
    table.insert(lines, '  (New-Object System.Drawing.PointF($cx1, $cy1)),')
    table.insert(lines, '  (New-Object System.Drawing.PointF($cx2, $cy2)),')
    table.insert(lines, '  (New-Object System.Drawing.PointF($cx3, $cy3)),')
    table.insert(lines, '  (New-Object System.Drawing.PointF($cx4, $cy4))')
    table.insert(lines, ')')

    table.insert(lines, '$gp = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Alternate)')
    table.insert(lines, '$gp.AddRectangle([System.Drawing.Rectangle]::new(0, 0, $img.Width, $img.Height))')
    table.insert(lines, '$gp.AddPolygon($cropPoints)')
    table.insert(lines, '$cropDim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(128, 0, 0, 0))')
    table.insert(lines, '$g.FillPath($cropDim, $gp)')
    table.insert(lines, '$cropDim.Dispose()')
    table.insert(lines, '$gp.Dispose()')

    -- Draw crop border (white line)
    table.insert(lines, '$cropPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 255, 255, 255), [math]::Max(1, $pw / 2))')
    table.insert(lines, '$g.DrawPolygon($cropPen, $cropPoints)')
    table.insert(lines, '$cropPen.Dispose()')
  end

  for i, rect in ipairs(allCropRects) do
    local isEnabled = false
    for _, fl in ipairs(enabledFLs) do
      if fl == rect.focalLength then
        isEnabled = true
        break
      end
    end

    if isEnabled then
      local colorIndex = rect.colorIndex or (((i - 1) % #FOVRenderer.colorNames) + 1)
      local colorName = FOVRenderer.colorNames[colorIndex]
      local rgb = FOVRenderer.colorRGB[colorName]

      table.insert(lines, string.format(
        '$p = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(128, %d, %d, %d), $pw)',
        rgb[1], rgb[2], rgb[3]))

      table.insert(lines, string.format('$left = [math]::Floor(%d * $scaleX)', rect.left))
      table.insert(lines, string.format('$top = [math]::Floor(%d * $scaleY)', rect.top))
      table.insert(lines, string.format('$right = [math]::Floor(%d * $scaleX)', rect.left + rect.width))
      table.insert(lines, string.format('$bottom = [math]::Floor(%d * $scaleY)', rect.top + rect.height))

      -- Full rectangle outline
      table.insert(lines, '$g.DrawRectangle($p, $left, $top, ($right - $left), ($bottom - $top))')
      table.insert(lines, '$p.Dispose()')
    end
  end

  -- Dimming: fill 4 strips around the highlight rect
  if highlightFL and highlightFL > 0 then
    local hlRect = nil
    for _, rect in ipairs(allCropRects) do
      if rect.focalLength == highlightFL then
        hlRect = rect
        break
      end
    end

    if hlRect then
      table.insert(lines, '$dimBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(115, 0, 0, 0))')
      table.insert(lines, string.format('$hlLeft = [math]::Floor(%d * $scaleX)', hlRect.left))
      table.insert(lines, string.format('$hlTop = [math]::Floor(%d * $scaleY)', hlRect.top))
      table.insert(lines, string.format('$hlRight = [math]::Floor(%d * $scaleX)', hlRect.left + hlRect.width))
      table.insert(lines, string.format('$hlBottom = [math]::Floor(%d * $scaleY)', hlRect.top + hlRect.height))

      -- Top strip
      table.insert(lines, '$g.FillRectangle($dimBrush, 0, 0, $img.Width, $hlTop)')
      -- Bottom strip
      table.insert(lines, '$g.FillRectangle($dimBrush, 0, $hlBottom, $img.Width, ($img.Height - $hlBottom))')
      -- Left strip
      table.insert(lines, '$g.FillRectangle($dimBrush, 0, $hlTop, $hlLeft, ($hlBottom - $hlTop))')
      -- Right strip
      table.insert(lines, '$g.FillRectangle($dimBrush, $hlRight, $hlTop, ($img.Width - $hlRight), ($hlBottom - $hlTop))')
      table.insert(lines, '$dimBrush.Dispose()')
    end
  end

  table.insert(lines, '$g.Dispose()')
  table.insert(lines, '$img.Save("' .. outputPath .. '", [System.Drawing.Imaging.ImageFormat]::Jpeg)')
  table.insert(lines, '$img.Dispose()')

  local scriptFile = io.open(scriptPath, "w+b")
  scriptFile:write(table.concat(lines, "\r\n"))
  scriptFile:close()

  local cmdline = 'powershell -ExecutionPolicy Bypass -File "' .. scriptPath .. '"'
  LrTasks.execute('"' .. cmdline .. '"')

  LrTasks.sleep(0.02)
  LrTasks.yield()

  return outputPath
end

-- ============================================================
-- Unified image view with observer-based re-rendering
-- ============================================================

--[[
  Create the unified image view with observer-based re-rendering.
  Uses platform-appropriate renderer (macOS JXA or Windows PowerShell).
  Falls back to legacy corner PNGs on macOS if JXA rendering fails.

  Parameters:
    photo: LrPhoto object
    allCropRects: All crop rectangles (full-frame coordinates)
    croppedCropRects: All crop rectangles (cropped-frame coordinates), or nil
    props: Observable property table (must have viewMode, show_*, highlightFL)
    displayWidth/Height: Display dimensions for full-frame view
    imageWidth/Height: Full original image pixel dimensions
    croppedDisplayWidth/Height: Display dimensions for cropped view
    croppedWidth/Height: Cropped image pixel dimensions
    focalLengths: Array of all standard focal lengths (for observers)
    cropRect: Crop polygon for overlay, or nil if uncropped

  Returns: LrView element (f:picture bound to rendered image path)
--]]
function FOVRenderer.createUnifiedImageView(photo, allCropRects, croppedCropRects, props,
    displayWidth, displayHeight, imageWidth, imageHeight,
    croppedDisplayWidth, croppedDisplayHeight, croppedWidth, croppedHeight,
    focalLengths, cropRect)
  local f = LrView.osFactory()

  -- Export both base images upfront
  local uncroppedResult = FOVRenderer.exportUncropped(photo, displayWidth, displayHeight)
  local croppedBasePath = FOVRenderer.exportBaseImage(photo, croppedDisplayWidth, croppedDisplayHeight)
  local hasUncropped = uncroppedResult.isUncropped

  if not hasUncropped then
    props.renderWarning = "Full frame unavailable — showing cropped view only."
    props.viewMode = "cropped"
  end

  local renderCount = { value = 0 }
  local renderGen = { value = 0 }
  local useLegacy = false

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
    local highlightFL = props.highlightFL or 0

    -- Pick base image and coordinate system based on view mode
    local basePath, rects, dw, dh, iw, ih, activeCrop
    if props.viewMode == "full" and hasUncropped then
      basePath = uncroppedResult.path
      rects = allCropRects
      dw = displayWidth
      dh = displayHeight
      iw = imageWidth
      ih = imageHeight
      activeCrop = cropRect
    else
      basePath = croppedBasePath
      rects = croppedCropRects or allCropRects
      dw = croppedDisplayWidth
      dh = croppedDisplayHeight
      iw = croppedWidth
      ih = croppedHeight
      activeCrop = nil
    end

    local outputPath
    if WIN_ENV then
      outputPath = FOVRenderer.renderWindowsOverlay(
        basePath, rects, enabledFLs,
        dw, dh, iw, ih,
        renderCount.value, highlightFL, activeCrop
      )
    else
      outputPath = FOVRenderer.renderMacOverlay(
        basePath, rects, enabledFLs,
        dw, dh, iw, ih,
        renderCount.value, highlightFL, activeCrop
      )
    end

    if outputPath then
      props.overlayImagePath = outputPath
    end
  end

  -- Initial render (try JXA on macOS)
  rerender()

  -- If first render failed on macOS, fall back to legacy
  if not WIN_ENV and not props.overlayImagePath then
    useLegacy = true
  end

  if useLegacy then
    -- Fallback: legacy corner PNG overlays (no dimming, no full rectangles)
    props.renderWarning = "Full rectangle rendering unavailable. Showing corner markers instead."
    return FOVRenderer.createLegacyImageView(
      photo, allCropRects, props, displayWidth, displayHeight, imageWidth, imageHeight
    )
  end

  -- Debounced re-render on checkbox, highlight, or view mode changes
  local function scheduleRender()
    renderGen.value = renderGen.value + 1
    local myGen = renderGen.value
    LrTasks.startAsyncTask(function()
      LrTasks.sleep(0.15)
      if renderGen.value ~= myGen then return end
      rerender()
    end)
  end

  for _, fl in ipairs(focalLengths) do
    props:addObserver("show_" .. fl, function()
      scheduleRender()
    end)
  end

  props:addObserver("highlightFL", function()
    scheduleRender()
  end)

  props:addObserver("viewMode", function()
    scheduleRender()
  end)

  return f:picture {
    value = LrView.bind("overlayImagePath"),
    width = displayWidth,
    height = displayHeight,
  }
end

return FOVRenderer
