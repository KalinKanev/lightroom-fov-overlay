--[[
  FOV Overlay Plugin for Lightroom Classic

  Shows graphical overlays indicating the effective field of view
  at different focal lengths when cropping an image.
--]]

return {
  LrSdkVersion = 5.0,
  LrSdkMinimumVersion = 5.0,
  LrToolkitIdentifier = 'com.fovoverlay.plugin',
  LrPluginName = "FOV Overlay",

  LrLibraryMenuItems = {
    {
      title = "Show FOV Guides",
      file = "FOVOverlayDialog.lua",
      enabledWhen = "photosSelected"
    },
  },

  LrPluginInfoProvider = 'FOVInfoProvider.lua',
  LrInitPlugin = 'FOVInitPlugin.lua',

  VERSION = { major=1, minor=2, revision=2, build=1 },
}
