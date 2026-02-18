--[[
  FOVInfoProvider.lua

  Plugin info provider for FOV Overlay plugin.
  Handles plugin preferences, status display, and update checking.
--]]

local LrView      = import 'LrView'
local LrDialogs   = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrHttp      = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrTasks     = import 'LrTasks'

local FOVInfoProvider = {}

local Info = require 'Info'
local PLUGIN_VERSION = {
  major    = Info.VERSION.major,
  minor    = Info.VERSION.minor,
  revision = Info.VERSION.revision,
}

local GITHUB_API_URL     = "https://api.github.com/repos/KalinKanev/lightroom-fov-overlay/releases/latest"
local GITHUB_RELEASES_URL = "https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest"

--------------------------------------------------------------------------------
-- Update checking
--------------------------------------------------------------------------------

local function parseVersion(tagStr)
  if not tagStr then return nil end
  local major, minor, revision = tagStr:match("v(%d+)%.(%d+)%.(%d+)")
  if not major then return nil end
  return {
    major    = tonumber(major),
    minor    = tonumber(minor),
    revision = tonumber(revision),
  }
end

local function isNewer(remoteVer, localVer)
  if not remoteVer or not localVer then return false end
  if remoteVer.major ~= localVer.major then return remoteVer.major > localVer.major end
  if remoteVer.minor ~= localVer.minor then return remoteVer.minor > localVer.minor end
  return remoteVer.revision > localVer.revision
end

local function versionToString(ver)
  return string.format("%d.%d.%d", ver.major, ver.minor, ver.revision)
end

local function checkForUpdate()
  local body, headers = LrHttp.get(GITHUB_API_URL)

  if not headers or headers.status ~= 200 then
    return nil, "Unable to reach GitHub. Please check your internet connection."
  end

  local tagName = body:match('"tag_name"%s*:%s*"([^"]+)"')
  if not tagName then
    return nil, "Could not parse release information from GitHub."
  end

  local remoteVer = parseVersion(tagName)
  if not remoteVer then
    return nil, "Could not parse version from tag: " .. tagName
  end

  return {
    available      = isNewer(remoteVer, PLUGIN_VERSION),
    tagName        = tagName,
    currentVersion = versionToString(PLUGIN_VERSION),
    remoteVersion  = versionToString(remoteVer),
  }
end

local function autoInstall(tagName)
  local pluginPath = _PLUGIN.path
  local zipURL = "https://github.com/KalinKanev/lightroom-fov-overlay/archive/refs/tags/" .. tagName .. ".zip"

  local tmpDir = LrPathUtils.getStandardFilePath("temp")

  local zipPath    = LrPathUtils.child(tmpDir, "fov-update.zip")
  local extractDir = LrPathUtils.child(tmpDir, "fov-update")

  -- Download the zip file
  local body, headers = LrHttp.get(zipURL)
  if not headers or headers.status ~= 200 then
    return false, "Failed to download update from GitHub (HTTP " .. tostring(headers and headers.status or "?") .. ")."
  end

  -- Write zip to temp file
  local zipFile = io.open(zipPath, "wb")
  if not zipFile then
    return false, "Failed to create temporary file: " .. zipPath
  end
  zipFile:write(body)
  zipFile:close()

  -- Clean up any previous extraction
  if WIN_ENV then
    LrTasks.execute('if exist "' .. extractDir .. '" rmdir /s /q "' .. extractDir .. '"')
  else
    LrTasks.execute('rm -rf "' .. extractDir .. '"')
  end

  -- Extract zip
  local extractCmd
  if WIN_ENV then
    extractCmd = 'powershell -Command "Expand-Archive -Path \'' .. zipPath .. '\' -DestinationPath \'' .. extractDir .. '\' -Force"'
  else
    extractCmd = 'unzip -o "' .. zipPath .. '" -d "' .. extractDir .. '"'
  end

  local rc = LrTasks.execute(extractCmd)
  if rc ~= 0 then
    return false, "Failed to extract update archive (exit code " .. tostring(rc) .. ")."
  end

  -- Copy extracted plugin contents over the current plugin path
  -- The zip extracts to: fov-update/lightroom-fov-overlay-<tag>/fovoverlay.lrplugin/
  local copyCmd
  if WIN_ENV then
    copyCmd = 'powershell -Command "Copy-Item -Recurse -Force \'' .. extractDir .. '\\*\\fovoverlay.lrplugin\\*\' \'' .. pluginPath .. '\\\'"'
  else
    copyCmd = 'cp -R "' .. extractDir .. '"/*/fovoverlay.lrplugin/* "' .. pluginPath .. '/"'
  end

  rc = LrTasks.execute(copyCmd)
  if rc ~= 0 then
    return false, "Failed to copy updated files to plugin directory (exit code " .. tostring(rc) .. ")."
  end

  -- Clean up temp files
  if WIN_ENV then
    LrTasks.execute('del "' .. zipPath .. '" 2>nul')
    LrTasks.execute('rmdir /s /q "' .. extractDir .. '"')
  else
    LrTasks.execute('rm -f "' .. zipPath .. '"')
    LrTasks.execute('rm -rf "' .. extractDir .. '"')
  end

  return true
end

local function checkAndPrompt()
  local result, err = checkForUpdate()

  if not result then
    LrDialogs.message("Update Check Failed", err, "warning")
    return
  end

  if not result.available then
    LrDialogs.message(
      "FOV Overlay is Up to Date",
      "You are running the latest version (v" .. result.currentVersion .. ")."
    )
    return
  end

  local action = LrDialogs.confirm(
    "Update Available",
    "A new version of FOV Overlay is available!\n\n" ..
    "Current version: v" .. result.currentVersion .. "\n" ..
    "Latest version:  " .. result.tagName .. "\n\n" ..
    "Would you like to download and install it automatically?",
    "Download & Install",
    "Cancel",
    "Open Download Page"
  )

  if action == "ok" then
    local success, installErr = autoInstall(result.tagName)
    if success then
      LrDialogs.message(
        "Update Installed Successfully",
        "FOV Overlay has been updated to " .. result.tagName .. ".\n\n" ..
        "Please reload the plugin to apply the update:\n" ..
        "File > Plug-in Manager > select FOV Overlay > Reload Plug-in"
      )
    else
      LrDialogs.message("Update Failed", installErr, "warning")
    end
  elseif action == "other" then
    LrHttp.openUrlInBrowser(GITHUB_RELEASES_URL)
  end
end

--------------------------------------------------------------------------------
-- Plugin Manager sections
--------------------------------------------------------------------------------

function FOVInfoProvider.sectionsForTopOfDialog(f, _)
  return {
    {
      title = "FOV Overlay Plugin",
      synopsis = "Field of View crop visualization",

      f:row {
        f:static_text {
          title = "Shows graphical overlays indicating the effective field of view\nat different focal lengths when cropping an image.",
          fill_horizontal = 1,
        },
      },

      f:row {
        f:static_text {
          title = "Usage:",
          font = "<system/bold>",
        },
      },

      f:row {
        f:static_text {
          title = "1. Select a photo in the Library module\n2. Go to Library > Plug-in Extras > Show FOV Guides\n3. View the crop rectangles for different focal lengths",
          fill_horizontal = 1,
        },
      },

      f:row {
        f:static_text {
          title = "\nExample: A photo shot at 300mm will show crop rectangles for\n400mm, 500mm, 600mm etc., indicating how much to crop.",
          fill_horizontal = 1,
        },
      },
    },
  }
end

function FOVInfoProvider.sectionsForBottomOfDialog(f, _)
  return {
    {
      title = "About",

      f:row {
        f:static_text {
          title = "FOV Overlay Plugin v" .. versionToString(PLUGIN_VERSION),
        },
      },

      f:row {
        f:static_text {
          title = "Calculates crop areas using the formula:\nCrop Ratio = Target FL / Original FL",
          font = "<system/small>",
        },
      },

      f:row {
        f:push_button {
          title = "Check for Updates",
          action = function()
            LrTasks.startAsyncTask(function()
              checkAndPrompt()
            end)
          end,
        },
      },
    },
  }
end

return FOVInfoProvider
