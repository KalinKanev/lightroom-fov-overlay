# FOV Overlay for Lightroom Classic

A plugin for Lightroom Classic (macOS and Windows) that shows graphical overlays indicating the equivalent field of view at different focal lengths when cropping an image.

Select a photo shot at a given focal length and instantly see crop rectangles for longer focal lengths — helping you decide how much to crop and what resolution you'll retain.

## Download

**[Download the latest release](https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest)**

## Features

- Visualize crop areas for standard focal lengths (24mm–1200mm)
- Toggle individual focal lengths on/off with checkboxes
- See remaining megapixels for each crop level
- Crop-aware: detects Lightroom crop and calculates the equivalent focal length
- Screen-aware dialog sizing — fits any display
- 10 distinct color-coded corner overlays

## Installation

1. Download the [latest release](https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest) zip file.

2. Unzip and locate the `fovoverlay.lrplugin` folder inside.

3. Find the folder where you keep your Lightroom plugins. If you don't know where this is, open Lightroom, go to `File > Plug-in Manager` and click `Add`. This will open a dialog in Lightroom's default plugin folder.

4. Copy the `fovoverlay.lrplugin` folder to your Lightroom plugins folder. Typical locations:
   - **macOS**: `~/Library/Application Support/Adobe/Lightroom/Modules/`
   - **Windows**: `C:\Users\<username>\AppData\Roaming\Adobe\Lightroom\Modules\`

5. Open Lightroom and go to `File > Plug-in Manager`.
   - **New installation**: Click `Add` and select the `fovoverlay.lrplugin` folder.
   - **Update**: Select the plugin and click `Reload Plug-in`.

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

| Color  | Meaning            |
|--------|--------------------|
| Green  | 1st selected FL    |
| Yellow | 2nd selected FL    |
| Orange | 3rd selected FL    |
| Red    | 4th selected FL    |

Colors cycle if more than 4 focal lengths are selected.

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

## License

MIT License. See [LICENSE](LICENSE) for details.
