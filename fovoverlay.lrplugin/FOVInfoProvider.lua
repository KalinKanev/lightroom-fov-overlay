--[[
  FOVInfoProvider.lua

  Plugin info provider for FOV Overlay plugin.
  Handles plugin preferences and status display.
--]]

local LrView = import 'LrView'
local LrHttp = import 'LrHttp'

local FOVInfoProvider = {}

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
          title = "FOV Overlay Plugin v1.0.1",
        },
      },

      f:row {
        f:static_text {
          title = "Calculates crop areas using the formula:\nCrop Ratio = Target FL / Original FL",
          font = "<system/small>",
        },
      },
    },
  }
end

return FOVInfoProvider
