--[[

╔════════════════════════════════╗
║        MPV stylesmanager       ║
║             v1.0.9             ║
╚════════════════════════════════╝

Style Properties: Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, ScaleX, ScaleY, Spacing, Outline, Shadow, Alignment, MarginL, MarginR, MarginV

]]

local options = require 'mp.options'
local utils   = require "mp.utils"
local assdraw = require "mp.assdraw"
local assline = require "assline"
local input   = require "input"
local path    = require "path"
local config  = {

    font_size          = 30,
    hint_font_size     = 19,
    padding            = 30,
    my_style           = "",
    properties_to_hide = "SecondaryColour,MarginL,MarginR",
    max_item           = 20
}

options.read_options(config, "stylesmanager")

local overlay              = mp.create_osd_overlay("ass-events")
local textOverlay          = mp.create_osd_overlay("ass-events")
textOverlay.compute_bounds = true
textOverlay.hidden         = true
local styles               = {original = {}, overrides = {}, onscreen = {}, editable = {}}
local page                 = "styles"
local index                = {styles = 1, editstyle = 1}
local map                  = {}
local colors               = {selected = "FFFF00"}
local data                 = {}
local opened               = false
local changed              = false
local resampleRes          = {sWidth = 0, sHeight = 0, dWidth = 1920, dHeight = 1080}

local function hash(str)

    local h1, h2, h3 = 0, 0, 0

    for i = 1, #str do

        local b = str:byte(i)

        h1 = (h1 * 31 + b) % 2^32
        h2 = (h2 * 37 + b) % 2^32
        h3 = (h3 * 41 + b) % 2^32
    end

    return string.format("%08x%08x%08x", h1, h2, h3)
end

local function runCommand(args)

    return mp.command_native({

        name           = 'subprocess',
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true,
        args           = args
    })
end

local function getPath(key)

    local hash       = hash(utils.split_path(mp.get_property("path")))
    local tempFolder = "mpvstylesmanager"

    if key == "cache" then

        return path.join({"%temp", tempFolder})
    elseif key == "overridefile" then

        return path.join({"%temp", tempFolder, hash..".json"})
    elseif key == "overridefile/converted" then

        return path.join({"%temp", tempFolder, hash..".converted.json"})
    end

    return nil
end

local function convertColor(colorCode, colorType)

    if colorType == "BGR" then

        local b, g, r = colorCode:sub(1, 2), colorCode:sub(3, 4), colorCode:sub(5, 6)

        return r..g..b
    elseif colorType == "RGB" then

        local r, g, b = colorCode:sub(1, 2), colorCode:sub(3, 4), colorCode:sub(5, 6)

        return b..g..r
    end
end

for key in pairs(colors) do colors[key] = convertColor(colors[key], "RGB") end

local function calculateTextWidth(line)

    textOverlay.res_x, textOverlay.res_y = mp.get_osd_size()
    textOverlay.data                     = line
    local res                            = textOverlay:update()

    return (res and res.x1) and (res.x1 - res.x0) or 0
end

local function tableMerge(t1, t2)

    local t3 = {}

    for k, v in pairs(t1) do t3[k] = v end
    for k, v in pairs(t2) do t3[k] = v end

    return t3
end

local function log(str)

    if type(str) == "table" then

        print(utils.format_json(str))
    else

        print(str)
    end
end

local function getScaledResolution()

    local w, h        = mp.get_osd_size()
    local scaleFactor = h / 1080

    return w / scaleFactor, h / scaleFactor
end

local function fillData()

    data.screenWidth, data.screenHeight = getScaledResolution()
    data.borderSize                     = mp.get_property_number('osd-border-size')
    data.tab                            = string.rep("\\h", 4)
    data.propertyNames                  = {

        Fontname        = "Font",
        Fontsize        = "Size",
        PrimaryColour   = "Color",
        SecondaryColour = "Transition Color",
        OutlineColour   = "Border Color",
        BackColour      = "Shadow Color",
        ScaleX          = "Scale X",
        ScaleY          = "Scale Y",
        Outline         = "Border",
        Alignment       = "Position",
        MarginV         = "Vertical Align",
        MarginL         = "Left Align",
        MarginR         = "Right Align"
    }
    data.editedSymbol                   = "*"
    data.rx, data.ry                    = resampleRes.sWidth / resampleRes.dWidth, resampleRes.sHeight / resampleRes.dHeight
    data.columns                        = {0, calculateTextWidth(string.format("{\\bord%s\\b1\\fs%s}● %s%s", data.borderSize, config.font_size, data.editedSymbol, string.rep("A", 14)))}
end

local function loadStyles(metadata)

    for style in metadata:gmatch("Style:[^\n]+") do

        style = assline:new(style)

        if style then

            for _, name in pairs(styles.editable) do

                if style[name] ~= nil and map[name] and map[name].getValue then

                    style[name] = map[name].getValue(style[name])
                end
            end

            table.insert(styles.original, style)
        end
    end
end

local function getEditableValues()

    local all = {

        "Fontname", "Fontsize",
        "PrimaryColour", "SecondaryColour", "OutlineColour", "BackColour",
        "Bold", "Italic",
        "ScaleX", "ScaleY", "Spacing",
        "Outline", "Shadow",
        "Alignment", "MarginV", "MarginR", "MarginL"
    }

    local excluded = {}

    for v in string.gmatch(config.properties_to_hide, "([^,]+)") do

        excluded[v] = true
    end

    local values = {}

    for _, v in ipairs(all) do

        if not excluded[v] then table.insert(values, v) end
    end

    return values
end

local function serializeStyle(styleName, style)

    local list = {}

    for _, property in pairs(styles.editable) do

        if style[property] ~= nil then

            table.insert(list, string.format("%s.%s=%s", styleName, property, style[property]))
        end
    end

    if #list == 0 then return "" end

    return table.concat(list, ",")
end

local function lastChanges(line)

    line = string.gsub(line, "(Colour)=([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]),([0-9A-Fa-f][0-9A-Fa-f])", function(p, color, alpha)

        return string.format("%s=&H%s%s&", p, alpha, convertColor(color, "RGB"))
    end)

    line = string.gsub(line, "(Scale[XY])=(%d+)", function(p, val)

        return string.format("%s=%s", p, val / 100)
    end)

    local alignments = {

        ["4"] = "9",
        ["5"] = "10",
        ["6"] = "11",
        ["7"] = "5",
        ["8"] = "6",
        ["9"] = "7"
    }

    line = string.gsub(line, "(Alignment)=([4-9])", function(p, val)

        return string.format("%s=%s", p, alignments[val])
    end)

    return line
end

local function getStyleOverrides()

    local overrides = {}

    for s, v in pairs(styles.overrides) do

        v = serializeStyle(s, v)
        v = lastChanges(v)

        table.insert(overrides, v)
    end

    return #overrides > 0 and table.concat(overrides, ",") or ""
end

local function applyStyleOverrides()

    local overrides = getStyleOverrides()

    if overrides == mp.get_property("sub-ass-style-overrides", "") then return end

    mp.set_property("sub-ass-style-overrides", overrides)
end

local function generateMap()

    return {

        Fontname = {

            setRange = function()

                input.max = 70
            end
        },

        Fontsize = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 1
                input.max         = 300
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 25 end

                return v
            end,

            resample = function(v)

                v = tonumber(v)

                return tostring(math.floor(v * data.ry + 0.5))
            end
        },

        Bold = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 1
            end,

            getValue = function (v)

                return v and 1 or 0
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end
        },

        Italic = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 1
            end,

            getValue = function (v)

                return v and 1 or 0
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end
        },

        PrimaryColour = {

            setRange = function()

                input.format = "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f],[0-9A-Fa-f][0-9A-Fa-f]"
            end,

            getValue = function (v)

                local alpha, color = v:match("([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])")

                if not alpha then return string.format("%s,%s", "000000", "00") end

                return string.format("%s,%s", convertColor(color, "BGR"), alpha)
            end
        },

        SecondaryColour = {

            setRange = function()

                input.format = "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f],[0-9A-Fa-f][0-9A-Fa-f]"
            end,

            getValue = function (v)

                local alpha, color = v:match("([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])")

                if not alpha then return string.format("%s,%s", "000000", "00") end

                return string.format("%s,%s", convertColor(color, "BGR"), alpha)
            end
        },

        OutlineColour = {

            setRange = function()

                input.format = "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f],[0-9A-Fa-f][0-9A-Fa-f]"
            end,

            getValue = function (v)

                local alpha, color = v:match("([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])")

                if not alpha then return string.format("%s,%s", "000000", "00") end

                return string.format("%s,%s", convertColor(color, "BGR"), alpha)
            end
        },

        BackColour = {

            setRange = function()

                input.format = "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f],[0-9A-Fa-f][0-9A-Fa-f]"
            end,

            getValue = function (v)

                local alpha, color = v:match("([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])")

                if not alpha then return string.format("%s,%s", "000000", "00") end

                return string.format("%s,%s", convertColor(color, "BGR"), alpha)
            end
        },

        ScaleX = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 1000
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 100 end

                return v
            end
        },

        ScaleY = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 1000
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 100 end

                return v
            end
        },

        Spacing = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 10
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end,

            resample = function(v)

                v = tonumber(v)

                return tostring(math.floor(v * data.ry))
            end
        },

        Outline = {

            setRange = function()

                input.accept_only = "float"
                input.min         = 0
                input.max         = 50
            end,

            getValue = function (v)

                if not tonumber(v) then return 0 end

                v = string.gsub(tostring(v), "(%.%d)%d+", "%1")

                return v
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end,

            resample = function(v)

                v = tonumber(v)

                if v == 0 then return "0" end

                return string.format("%.1f", v * data.ry)
            end
        },

        Shadow = {

            setRange = function()

                input.accept_only = "float"
                input.min         = 0
                input.max         = 50
            end,

            getValue = function (v)

                if not tonumber(v) then return 0 end

                v = string.gsub(tostring(v), "(%.%d)%d+", "%1")

                return v
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end,

            resample = function(v)

                v = tonumber(v)

                if v == 0 then return "0" end

                return string.format("%.1f", v * data.ry)
            end
        },

        Alignment = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 1
                input.max         = 9
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 1 end

                return v
            end
        },

        MarginV = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 2000
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end,

            resample = function(v)

                v = tonumber(v)

                return tostring(math.floor(v * data.ry + 0.5))
            end
        },

        MarginR = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 2000
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end,

            resample = function(v)

                v = tonumber(v)

                return tostring(math.floor(v * data.rx + 0.5))
            end
        },

        MarginL = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 2000
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end,

            resample = function(v)

                v = tonumber(v)

                return tostring(math.floor(v * data.rx + 0.5))
            end
        }
    }
end

local function updateOverlay(content, x, y)

    if overlay.data == content and overlay.res_x == data.screenWidth and overlay.res_y == data.screenHeight then return end

    overlay.data  = content
    overlay.res_x = (x and x > 0) and x or data.screenWidth
    overlay.res_y = (y and y > 0) and x or data.screenHeight
    overlay.z     = 2000

    overlay:update()
end

local function render()

    local lineY = config.padding
    local ass   = assdraw.ass_new()

    if page == "styles" then

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY)
        ass:append(string.format("{\\bord%s\\b1\\fs%s}", data.borderSize, config.font_size))
        ass:append(string.format("[%s/%s] Styles", index.styles, #styles.original))

        lineY = lineY + config.font_size

        local halfItems = math.floor(config.max_item / 2)
        local sIndex    = math.max(index.styles - halfItems, 1)
        local mIndex    = sIndex + config.max_item - 1

        if mIndex > #styles.original then

            mIndex = #styles.original
            sIndex = math.max(mIndex - config.max_item + 1, 1)
        end

        for i = sIndex, mIndex do

            local styleName = styles.original[i].Name
            local edited    = styles.overrides[styleName]

            ass:new_event()
            ass:an(7)
            ass:pos(config.padding + data.columns[1], lineY)
            ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size))

            if styles.onscreen[styleName] then

                ass:append(string.format("{\\c%s}", colors.selected))
            end

            if i == index.styles then

                ass:append(string.format("{\\b1}● %s%s{\\b0}", edited and data.editedSymbol or "", styleName))
            else

                ass:append(string.format("○ %s%s", edited and data.editedSymbol or "", styleName))
            end

            lineY = lineY + config.font_size
        end
    elseif page == "editstyle" or page == "editvalue" then

        local styleName = styles.original[index.styles].Name

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY)
        ass:append(string.format("{\\bord%s\\b1\\fs%s}", data.borderSize, config.font_size))
        ass:append(string.format("← Edit style: \"%s\"", styleName))

        lineY = lineY + config.font_size

        for i, property in pairs(styles.editable) do

            local edited = styles.overrides[styleName] and styles.overrides[styleName][property]

            ass:new_event()
            ass:an(7)
            ass:pos(config.padding + data.columns[1], lineY)
            ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size))

            if i == index.editstyle then

                ass:append(string.format("{\\b1}● %s%s{\\b0}", edited and data.editedSymbol or "", data.propertyNames[property] or property))
            else

                ass:append(string.format("○ %s%s", edited and data.editedSymbol or "", data.propertyNames[property] or property))
            end

            if page == "editstyle" or (page == "editvalue" and i ~= index.editstyle) then

                ass:new_event()
                ass:an(7)
                ass:pos(config.padding + data.columns[2], lineY)
                ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size))

                if edited then

                    ass:append(styles.overrides[styleName][property])
                else

                    ass:append(styles.original[index.styles][property])
                end
            else

                local text, textWithCursor = input.texts()

                --input

                ass:new_event()
                ass:an(7)
                ass:pos(config.padding + data.columns[2], lineY)
                ass:append(text)

                --cursor

                ass:new_event()
                ass:pos(config.padding + data.columns[2], lineY)
                ass:append(textWithCursor)
            end

            lineY = lineY + config.font_size
        end
    end

    lineY = lineY + config.padding

    ass:new_event()
    ass:an(7)
    ass:pos(config.padding, lineY)
    ass:append(string.format("{\\bord%s\\b0\\fs%s}", data.borderSize, config.hint_font_size))
    ass:append("Navigation")

    lineY = lineY + config.hint_font_size * 1.5

    ass:new_event()
    ass:an(7)
    ass:pos(config.padding, lineY)
    ass:append(string.format("{\\bord%s\\b0\\fs%s}", data.borderSize, config.hint_font_size))
    ass:append(string.format("%s"..data.tab.."%s", "<LEFT-RIGHT> Back / Edit", "<UP-DOWN> Prev / Next Item"))

    lineY = lineY + config.hint_font_size * 1.5

    ass:new_event()
    ass:an(7)
    ass:pos(config.padding, lineY)
    ass:append(string.format("{\\bord%s\\b0\\fs%s}", data.borderSize, config.hint_font_size))
    ass:append("Actions")

    if page == "styles" then

        lineY = lineY + config.hint_font_size * 1.5

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY)
        ass:append(string.format("{\\bord%s\\b0\\fs%s}", data.borderSize, config.hint_font_size))
        ass:append(string.format("%s"..data.tab.."%s"..data.tab.."%s", "<DEL> Reset", "<SHIFT+DEL> Reset all", "<ESC> Exit"))

        lineY = lineY + config.hint_font_size + config.padding

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY)
        ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.hint_font_size))
        ass:append("Styles of the lines currently visible on screen will be highlighted in yellow.")
    else

        lineY = lineY + config.hint_font_size * 1.5

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY)
        ass:append(string.format("{\\bord%s\\b0\\fs%s}", data.borderSize, config.hint_font_size))
        ass:append(string.format("%s"..data.tab.."%s"..data.tab.."%s"..data.tab.."%s"..data.tab.."%s", "<ENTER> Confirm", "<DEL> Reset value", "<SHIFT+DEL> Reset style", "<O> Load your style", "<ESC> Exit"))
    end

    --update

    updateOverlay(ass.text)
end

local function handleEdit()

    local p = styles.editable[index.editstyle]
    local s = styles.original[index.styles].Name

    input.init()

    input.theme     = "black"
    input.font_size = config.font_size

    if map[p] then map[p].setRange() end

    if styles.overrides[s] and styles.overrides[s][p] then

        input.default(styles.overrides[s][p])
    else

        input.default(styles.original[index.styles][p])
    end

    unsetBindings("editstyle")
    setBindings("editvalue")

    render()
end

local function loadScreenStyles()

    local subtitleLinesOnScreen = mp.get_property("sub-text/ass-full", "")

    if subtitleLinesOnScreen == "" then return end

    for line in subtitleLinesOnScreen:gmatch("Dialogue:[^\n]+") do

        line = assline:new(line)

        if line then styles.onscreen[line.Style] = true end
    end
end

local function resetValue(all)

    local p = styles.editable[index.editstyle]
    local s = styles.original[index.styles].Name

    if all then

        if page == "styles" and next(styles.overrides) ~= nil then

            changed          = true
            styles.overrides = {}
        elseif page == "editstyle" and styles.overrides[s] then

            changed             = true
            styles.overrides[s] = nil
        end
    else

        if page == "styles" and styles.overrides[s] then

            changed             = true
            styles.overrides[s] = nil
        elseif page == "editstyle" and styles.overrides[s] and styles.overrides[s][p] then

            changed                = true
            styles.overrides[s][p] = nil

            if next(styles.overrides[s]) == nil then styles.overrides[s] = nil end
        end
    end
end

local function changeValue(newValue, property)

    changed = true
    local p = property or styles.editable[index.editstyle]
    local s = styles.original[index.styles].Name

    if not styles.overrides[s] then styles.overrides[s] = {} end

    if tostring(styles.original[index.styles][p]) == newValue then

        styles.overrides[s][p] = nil
    else

        styles.overrides[s][p] = (map[p] and map[p].setValue) and map[p].setValue(newValue) or newValue
    end
end

local function reset()

    styles.original     = {}
    styles.overrides    = {}
    styles.onscreen     = {}
    styles.editable     = {}
    index.styles        = 1
    index.editstyle     = 1
    data                = {}
    map                 = {}
    page                = "styles"
    changed             = false
    resampleRes.sWidth  = 0
    resampleRes.sHeight = 0
end

local function writeToCache()

    if not changed then return end

    path.createDir(getPath("cache"))

    local file
    local newOverrides = getStyleOverrides()

    if newOverrides == "" then

        for _, k in pairs({"overridefile", "overridefile/converted"}) do

            path.removeFile(getPath(k))
        end

        return
    end

    for _, k in pairs({"overridefile", "overridefile/converted"}) do

        local ok = path.createFile(getPath(k), k == "overridefile" and utils.format_json(styles.overrides) or newOverrides)

        if not ok then mp.osd_message("Config file not created!", 3) end
    end

    print(string.format("Saved style overrides: \"%s\"", newOverrides))
end

local function readFromCache(fileType)

    if fileType == "overridefile" then

        local content = path.readFile(getPath(fileType))

        if not content then return end

        styles.overrides = utils.parse_json(content)
    elseif fileType == "overridefile/converted" then

        local content = path.readFile(getPath(fileType))

        if not content then return end

        print(string.format("Loaded style overrides: \"%s\"", content))

        mp.set_property("sub-ass-style-overrides", content)
    end
end

local function toggle(section)

    if not opened then

        local overrideMode = mp.get_property("sub-ass-override", "")

        if not (overrideMode == "yes" or overrideMode == "scale") then mp.osd_message("Style override functionality only works with \"--sub-ass-override=yes\" or \"--sub-ass-override=scale\".", 3) return end

        local metadata = mp.get_property("sub-ass-extradata", "")

        if metadata == "" then mp.osd_message("Missing metadata! This is not an ASS file.", 3) return end

        resampleRes.sWidth  = tonumber(metadata:match("PlayResX: (%d+)")) or 0
        resampleRes.sHeight = tonumber(metadata:match("PlayResY: (%d+)")) or 0

        fillData()
        loadScreenStyles()

        map             = generateMap()
        styles.editable = getEditableValues()

        loadStyles(metadata)

        if #styles.original == 0 then

            reset()
            collectgarbage()

            mp.osd_message("Failed to parse styles.", 3)

            return
        end

        readFromCache("overridefile")
        render()
        setBindings(section)
    else

        writeToCache()
        unsetBindings(section)
        updateOverlay("", 0, 0)

        input.reset()
        reset()
        collectgarbage()
    end

    opened = not opened
end

local function bindingList(section)

    local inputBindings, defaultBindings = {}, {}

    if section == "styles" then

        defaultBindings = {

            close = {

                key  = "esc",
                func = function ()

                    toggle("styles")
                end,
                opts = nil
            },

            previtem = {

                key  = "up",
                func = function ()

                    index.styles = math.max(index.styles - 1, 1)

                    render()
                end,
                opts = {repeatable = true}
            },

            nextitem = {

                key  = "down",
                func = function ()

                    index.styles = math.min(index.styles + 1, #styles.original)

                    render()
                end,
                opts = {repeatable = true}
            },

            editstyle = {

                key  = "right",
                func = function ()

                    page = "editstyle"

                    unsetBindings("styles")
                    setBindings("editstyle")

                    render()
                end,
                opts = {repeatable = true}
            },

            disableback = {

                key  = "left",
                func = function ()

                end,
                opts = nil
            },

            resetstyle = {

                key  = "del",
                func = function ()

                    resetValue()
                    applyStyleOverrides()
                    render()
                end,
                opts = nil
            },

            resetallstyles = {

                key  = "shift+del",
                func = function ()

                    resetValue(true)
                    applyStyleOverrides()
                    render()
                end,
                opts = nil
            },

            disableenter = {

                key  = "enter",
                func = function ()

                end,
                opts = nil
            },
        }
    elseif section == "editstyle" then

        defaultBindings = {

            close = {

                key  = "esc",
                func = function ()

                    toggle("editstyle")
                end,
                opts = nil
            },

            previtem = {

                key  = "up",
                func = function ()

                    index.editstyle = math.max(index.editstyle - 1, 1)

                    render()
                end,
                opts = {repeatable = true}
            },

            nextitem = {

                key  = "down",
                func = function ()

                    index.editstyle = math.min(index.editstyle + 1, #styles.editable)

                    render()
                end,
                opts = {repeatable = true}
            },

            editvalue = {

                key  = "right",
                func = function ()

                    page = "editvalue"

                    handleEdit()
                end,
                opts = nil
            },

            resetvalue = {

                key  = "del",
                func = function ()

                    resetValue()
                    applyStyleOverrides()
                    render()
                end,
                opts = nil
            },

            resetstyle = {

                key  = "shift+del",
                func = function ()

                    resetValue(true)
                    applyStyleOverrides()
                    render()
                end,
                opts = nil
            },

            loadefaultstyle = {

                key  = "o",
                func = function ()

                    if config.my_style == "" then return end

                    local changed        = false
                    local shouldResample = resampleRes.sWidth > 0 and resampleRes.sWidth ~= resampleRes.dWidth and resampleRes.sHeight > 0 and resampleRes.sHeight ~= resampleRes.dHeight

                    for p, v in config.my_style:gmatch("([^:,]+):([^:,]+)") do

                        input.init()

                        input.font_size = config.font_size

                        if map[p] then

                            map[p].setRange()

                            v = map[p].getValue and map[p].getValue(v) or v

                            if input.default(v) then

                                changed = true

                                changeValue(shouldResample and map[p].resample and map[p].resample(input.get_text()) or input.get_text(), p)
                            else

                                mp.msg.warn(string.format("Value is out of allowed range: %s (%s)", v, p))
                            end
                        else

                            mp.msg.warn(string.format("This property has no defined handler: %s", p))
                        end
                    end

                    if changed then

                        if shouldResample then print(string.format("Resampling applied: %sx%s > %sx%s", resampleRes.sWidth, resampleRes.sHeight, resampleRes.dWidth, resampleRes.dHeight)) end

                        applyStyleOverrides()
                        render()
                    end
                end,
                opts = nil
            },

            backstyles = {

                key  = "left",
                func = function ()

                    page = "styles"

                    unsetBindings("editstyle")
                    setBindings("styles")

                    render()
                end,
                opts = nil
            },

            disableenter = {

                key  = "enter",
                func = function ()

                end,
                opts = nil
            },
        }

        defaultBindings["loadefaultstylealt"] = {

            key  = "O",
            func = defaultBindings["loadefaultstyle"].func,
            opts = defaultBindings["loadefaultstyle"].opts
        }
    elseif section == "editvalue" then

        inputBindings = input.bindings({

            after_changes = function()

                render()
            end,

            edit_clipboard = function(text)

                local property = styles.editable[index.editstyle]

                if property and string.find(property, "Colour") and #text == 6 then

                    text = text..",00"
                end

                return text
            end
        })

        defaultBindings = {

            close = {

                key  = "esc",
                func = function ()

                    page = "editstyle"

                    unsetBindings("editvalue")
                    setBindings("editstyle")

                    render()
                end,
                opts = nil
            },

            click = {

                key  = "mbtn_left",
                func = function ()

                    page = "editstyle"

                    unsetBindings("editvalue")
                    setBindings("editstyle")

                    render()
                end,
                opts = nil
            },

            enter = {

                key  = "enter",
                func = function ()

                    page = "editstyle"

                    unsetBindings("editvalue")
                    setBindings("editstyle")
                    changeValue(input.get_text())
                    applyStyleOverrides()
                    render()
                end,
                opts = nil
            },

            previtem = {

                key  = "up",
                func = function ()

                    changeValue(input.get_text())
                    applyStyleOverrides()

                    index.editstyle = math.max(index.editstyle - 1, 1)

                    handleEdit()
                end,
                opts = {repeatable = true}
            },

            disableup = {

                key  = "down",
                func = function ()

                    changeValue(input.get_text())
                    applyStyleOverrides()

                    index.editstyle = math.min(index.editstyle + 1, #styles.editable)

                    handleEdit()
                end,
                opts = {repeatable = true}
            },
        }
    end

    return tableMerge(defaultBindings, inputBindings)
end

function setBindings(section)

    for name, binding in pairs(bindingList(section)) do mp.add_forced_key_binding(binding.key, "stylesmanager_"..name, binding.func, binding.opts) end
end

function unsetBindings(section)

    for name in pairs(bindingList(section)) do mp.remove_key_binding("stylesmanager_"..name) end
end

mp.observe_property("osd-dimensions", "native", function (_, value)

    if opened then

        fillData()
        render()
    end
end)

mp.observe_property("sid", "number", function(_, value)

    if opened then toggle(page) end
end)

mp.register_event("file-loaded", function() readFromCache("overridefile/converted") end)

mp.add_key_binding(nil, "stylesmanager", function() toggle(page) end)