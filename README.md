# FOV Overlay for Lightroom Classic

A plugin for Lightroom Classic (macOS and Windows) that shows graphical overlays indicating the equivalent field of view at different focal lengths when cropping an image.

Select a photo shot at a given focal length and instantly see crop rectangles for longer focal lengths — helping you decide how much to crop and what resolution you'll retain.

<img src="screenshot.png" alt="FOV Overlay Dialog" width="700"/>

## Download

**[Download the latest release](https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest)** and see detailed **[installation instructions](#installation)**.

## Features

- Visualize crop areas for standard focal lengths (24mm–1200mm)
- Toggle individual focal lengths on/off with checkboxes
- See remaining megapixels for each crop level
- Crop-aware: detects Lightroom crop and calculates the equivalent focal length
- Screen-aware dialog sizing — fits any display
- 10 distinct color-coded corner overlays

## Installation

### macOS

Open Terminal and run:

```bash
# Download and unzip
cd ~/Downloads
curl -L https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest/download/source.zip -o fov-overlay.zip \
  || curl -L $(curl -s https://api.github.com/repos/KalinKanev/lightroom-fov-overlay/releases/latest | grep zipball_url | cut -d '"' -f 4) -o fov-overlay.zip
unzip fov-overlay.zip

# Remove old version (if updating)
rm -rf "$HOME/Library/Application Support/Adobe/Lightroom/Modules/fovoverlay.lrplugin"

# Install — adjust the folder name to match the extracted zip
cp -R KalinKanev-lightroom-fov-overlay-*/fovoverlay.lrplugin "$HOME/Library/Application Support/Adobe/Lightroom/Modules/"
```

Then in Lightroom: `File > Plug-in Manager` — click `Add` (new install) or `Reload Plug-in` (update).

### Windows

Open PowerShell and run:

```powershell
# Download and unzip
cd $env:USERPROFILE\Downloads
Invoke-WebRequest -Uri "https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest" -OutFile fov-overlay.zip -MaximumRedirection 5
Expand-Archive -Path fov-overlay.zip -DestinationPath fov-overlay -Force

# Remove old version (if updating)
Remove-Item -Recurse -Force "$env:APPDATA\Adobe\Lightroom\Modules\fovoverlay.lrplugin" -ErrorAction SilentlyContinue

# Install
Copy-Item -Recurse (Get-ChildItem fov-overlay\*\fovoverlay.lrplugin).FullName "$env:APPDATA\Adobe\Lightroom\Modules\"
```

Then in Lightroom: `File > Plug-in Manager` — click `Add` (new install) or `Reload Plug-in` (update).

### Manual installation

If you prefer not to use the command line:

1. **[Download the plugin package](https://github.com/KalinKanev/lightroom-fov-overlay/releases/latest)** — click "Source code (zip)".
2. Unzip and locate the `fovoverlay.lrplugin` folder inside.
3. If updating, remove the old `fovoverlay.lrplugin` from your plugins folder first.
4. Copy `fovoverlay.lrplugin` to your Lightroom plugins folder:
   - **macOS**: `~/Library/Application Support/Adobe/Lightroom/Modules/`
   - **Windows**: `%APPDATA%\Adobe\Lightroom\Modules\`
5. In Lightroom: `File > Plug-in Manager` — click `Add` (new install) or `Reload Plug-in` (update).

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
