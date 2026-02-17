--[[
  FOVInitPlugin.lua

  Runs once at Lightroom startup. Checks for plugin updates weekly.
--]]

local LrDialogs   = import 'LrDialogs'
local LrHttp      = import 'LrHttp'
local LrPrefs     = import 'LrPrefs'
local LrTasks     = import 'LrTasks'

local Info = require 'Info'

local GITHUB_API_URL      = "https://api.github.com/repos/KalinKanev/lightroom-fov-overlay/releases/latest"
local GITHUB_RELEASES_URL = "https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest"
local CHECK_INTERVAL      = 7 * 24 * 60 * 60  -- 7 days in seconds

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

LrTasks.startAsyncTask(function()
  local prefs = LrPrefs.prefsForPlugin()

  -- Check if enough time has passed since last check
  local now = os.time()
  local lastCheck = prefs.lastUpdateCheck or 0

  if (now - lastCheck) < CHECK_INTERVAL then
    return
  end

  -- Record that we checked (even if the fetch fails, avoid retrying every startup)
  prefs.lastUpdateCheck = now

  local body, headers = LrHttp.get(GITHUB_API_URL)
  if not headers or headers.status ~= 200 then
    return
  end

  local tagName = body:match('"tag_name"%s*:%s*"([^"]+)"')
  if not tagName then return end

  local remoteVer = parseVersion(tagName)
  if not remoteVer then return end

  local localVer = {
    major    = Info.VERSION.major,
    minor    = Info.VERSION.minor,
    revision = Info.VERSION.revision,
  }

  if not isNewer(remoteVer, localVer) then
    return
  end

  local currentStr = string.format("%d.%d.%d", localVer.major, localVer.minor, localVer.revision)

  local action = LrDialogs.confirm(
    "FOV Overlay Update Available",
    "A new version of FOV Overlay is available!\n\n" ..
    "Current version: v" .. currentStr .. "\n" ..
    "Latest version:  " .. tagName .. "\n\n" ..
    "You can update from the Plugin Manager.",
    "Open Plugin Manager Info",
    "Dismiss",
    "Open Download Page"
  )

  if action == "ok" then
    LrDialogs.message(
      "Update via Plugin Manager",
      "Go to File > Plug-in Manager, select FOV Overlay, " ..
      "and click \"Check for Updates\" to download and install."
    )
  elseif action == "other" then
    LrHttp.openUrlInBrowser(GITHUB_RELEASES_URL)
  end
end)
