# mpv-stylesmanager
An MPV plugin that allows modifying ASS styles.

![Example for Stylesmanager](https://github.com/magnum357i/mpv-stylesmanager/blob/main/stylesmanager.gif)

# What is it?
Allows you to modify style properties in ASS subtitles. Want to resize dialogue or change the font while watching anime? This plugin makes it easy.

**Important: If inline tags are present, your changes will have no visible effect.**

# Installation
Place `stylesmanager` folder into your scripts directory.

# Configuration
Create a file named `stylesmanager.conf` in the script-opts directory, and copy the content below into it. You can now modify the settings as desired.

```ini
# OSD Settings
font_size=18
hint_font_size=11
padding=20

# Default Style
# You can apply the properties you've defined here to the selected style with a single key press.
# Color format: <alpha><alpha><b><b><g><g><r><r>
# Example: 370DE2 (RGB) > E20D37 (BGR) > &H00E20D37 (ASS)
# You can convert any RGB value to BGR by swapping the first and last two characters. Just remember that the first two characters in an ASS color code represent the alpha channel.
# Available Properties: Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, ScaleX, ScaleY, Spacing, Outline, Shadow, Alignment, MarginL, MarginR, MarginV
my_style=Fontname:Cambria,Fontsize:50,PrimaryColour:&H00E20D37
```

# Key Bindings
By default, no keys are assigned. You can create your own bindings in input.conf:

```
Ctrl+b script-binding stylesmanager
```

# Saving
When you modify a style, it affects all files in that directory.

# Planned Features
- Scroll