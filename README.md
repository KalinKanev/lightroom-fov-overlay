# FOV Overlay for Lightroom Classic

A plugin for Lightroom Classic (macOS and Windows) that shows graphical overlays indicating the equivalent field of view at different focal lengths when cropping an image.

Select a photo shot at a given focal length and instantly see crop rectangles for longer focal lengths — helping you decide how much to crop and what resolution you'll retain.

<img src="screenshot.png" alt="FOV Overlay Dialog" width="700"/>

## Features

- Visualize crop areas for standard focal lengths (24mm–1200mm)
- Toggle individual focal lengths on/off with checkboxes
- See remaining megapixels for each crop level
- Crop-aware: detects Lightroom crop and calculates the equivalent focal length
- Screen-aware dialog sizing — fits any display
- 10 distinct color-coded overlays
- One-click update checking from Plugin Manager

## Installation

1. **[Download the latest release](https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest)** — click "Source code (zip)".
2. Unzip and locate the `fovoverlay.lrplugin` folder inside.
3. In Lightroom: `File > Plug-in Manager` — click `Add` and select the `fovoverlay.lrplugin` folder.

To update, use the **Check for Updates** button in the Plugin Manager, or repeat the steps above and click `Reload Plug-in`.

## Usage

1. Select a photo in the **Library** module.
2. Go to `Library > Plug-in Extras > Show FOV Guides`.
3. The dialog shows your image with crop rectangles for focal lengths longer than what the photo was shot at (or cropped to).
4. Use the checkboxes to toggle individual focal lengths on or off.
5. Click **Close** to dismiss the dialog.

### Cropped Images

If the selected photo has a Lightroom crop applied, the plugin automatically:
- Calculates the **equivalent focal length** based on the crop (e.g., a 200mm shot cropped to 50% width = 400mm equivalent)
- Shows the effective focal length in the header
- Only enables focal lengths longer than the equivalent
- Grays out focal lengths that are already exceeded by the crop

### Understanding the Overlays

Each overlay rectangle shows how much of the current image you would need to crop to match the field of view of a longer focal length. The megapixel count next to each checkbox tells you how much resolution remains after that crop.

Each selected focal length gets a unique color from the palette: green, yellow, orange, red, cyan, magenta, blue, lime, pink, white.

## Requirements

- Lightroom Classic (LR 5.7+, LR 6, or any Creative Cloud subscription version)
- macOS or Windows

## How It Works

The plugin reads the photo's EXIF focal length and image dimensions. For each target focal length, it computes:

```
Crop Ratio = Target FL / Original FL
Crop Width = Image Width / Crop Ratio
Crop Height = Image Height / Crop Ratio
```

The resulting rectangle is centered on the image and drawn as colored corner markers.

## Troubleshooting

### Overlay markers not showing

If the colored corner markers don't appear on the image:

1. Make sure the `assets` folder with all PNG files is present inside `fovoverlay.lrplugin`
2. Try removing and reinstalling the plugin using the commands above
3. In Lightroom: `File > Plug-in Manager`, select the plugin, click `Reload Plug-in`

### Dialog too large or Close button not visible

Make sure you're running the latest version. The plugin scales the dialog to fit your Lightroom window automatically.

## License

MIT License. See [LICENSE](LICENSE) for details.
