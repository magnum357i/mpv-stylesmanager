# mpv-stylesmanager
An MPV plugin that allows modifying ASS styles.

![Example for Stylesmanager](https://github.com/magnum357i/mpv-stylesmanager/blob/main/stylesmanager.gif)

# What is it?
Allows you to modify style properties in ASS subtitles. Want to resize dialogue or change the font while watching anime? This plugin makes it easy.

**Important: If inline tags are present, your changes will have no visible effect.**

# Installation

### Manual

Place `scripts` and `script-opts` folders into your config directory.

| OS        | Location         |
|-----------|------------------|
| Windows   | `%appdata%/mpv/` |
| GNU/Linux | `~/.config/mpv/` |

### Automatic

To install or update via command line:

#### Windows 10 (CMD)

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/magnum357i/mpv-stylesmanager/HEAD/installers/windows.ps1 | iex"
```

#### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/magnum357i/mpv-stylesmanager/HEAD/installers/linux.sh | sh
```

# Configuration
```ini
# OSD Settings
font_size=30
hint_font_size=19
padding=30

# Your Style
# With a single key press, you can apply the properties you've defined here to the selected style.
#
# Color format: <alpha><alpha><b><b><g><g><r><r>
# Example: 370DE2 (RGB) > E20D37 (BGR) > &H00E20D37 (ASS)
# You can convert any RGB value to BGR by swapping the first and last two characters. Just remember that the first two characters in an ASS color code represent the alpha channel.
#
# Available Properties: Name (Required), Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, ScaleX, ScaleY, Spacing, Outline, Shadow, Alignment, MarginL, MarginR, MarginV
style1=Name:General,Fontname:Calibri,Fontsize:72,PrimaryColour:&H00FFFFFF,OutlineColour:&H00000000,Bold:1,MarginV:40,Outline:4.2,Shadow:0,ScaleX:100,ScaleY:100,Spacing:0
style2=
style3=
style4=
style5=
style6=
style7=
style8=
style9=

# Don't show these items.
properties_to_hide=SecondaryColour,MarginL,MarginR

# Max Items to Display
max_items=20

# Sort styles by name.
sort_by_name=yes
```

# Key Bindings
By default, no keys are assigned. You can create your own bindings in `input.conf`:

```
Ctrl+b script-binding stylesmanager
```

# Saving
When you modify a style, it affects all files in that directory.