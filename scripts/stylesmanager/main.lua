--[[

╔════════════════════════════════╗
║        MPV stylesmanager       ║
║             v1.1.0             ║
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
    style1             = "",
    style2             = "",
    style3             = "",
    style4             = "",
    style5             = "",
    style6             = "",
    style7             = "",
    style8             = "",
    style9             = "",
    properties_to_hide = "SecondaryColour,MarginL,MarginR",
    max_items          = 20,
    sort_by_name       = false
}

options.read_options(config, "stylesmanager")

local overlay              = mp.create_osd_overlay("ass-events")
local textOverlay          = mp.create_osd_overlay("ass-events")
textOverlay.compute_bounds = true
textOverlay.hidden         = true
local styles               = {original = {}, overrides = {}, onscreen = {}, editable = {}, user = {}}
local page                 = "styles"
local prevPage             = ""
local index                = {styles = 1, editstyle = 1, userstyles = 1}
local map                  = {}
local colors               = {selected = "FFFF00"}
local data                 = {}
local opened               = false
local changed              = false
local resampleRes          = {sWidth = 1920, sHeight = 1080, dWidth = 0, dHeight = 0}
local scrollOffset         = 1

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
    data.rx, data.ry                    = resampleRes.dWidth / resampleRes.sWidth, resampleRes.dHeight / resampleRes.sHeight
    data.columnSpaces                   = {0, calculateTextWidth(string.format("{\\bord%s\\b1\\fs%s}● %s%s", data.borderSize, config.font_size, data.editedSymbol, string.rep("A", 14)))}
end

local function loadStyles(metadata)

    for style in assline:styles(metadata) do

        for _, name in pairs(styles.editable) do

            if style[name] ~= nil and map[name] and map[name].getValue then

                style[name] = map[name].getValue(style[name])
            end
        end

        table.insert(styles.original, style)
    end

    if config.sort_by_name then

        table.sort(styles.original, function(a, b)

            return a.Name < b.Name
        end)
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

    return next(list) == nil and "" or table.concat(list, ",")
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

    return next(overrides) == nil and "" or table.concat(overrides, ",")
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

    local ass   = assdraw.ass_new()
    local lineY = config.padding

    ass:new_event()
    ass:an(7)
    ass:pos(config.padding, lineY)
    ass:append(pages[page].title())

    lineY = lineY + config.font_size

    for columns in pages[page].rows() do

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding + data.columnSpaces[1], lineY)
        ass:append(columns[1])

        if columns[2] then

            for _, c in ipairs(columns[2]) do

                ass:new_event()
                ass:an(7)
                ass:pos(config.padding + data.columnSpaces[2], lineY)
                ass:append(c)
            end
        end

        lineY = lineY + config.font_size
    end

    lineY = lineY + config.font_size

    for rowText in pages[page].hint() do

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY)
        ass:append(rowText)

        lineY = lineY + config.hint_font_size
    end

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
end

local function loadScreenStyles()

    local subtitleLinesOnScreen = mp.get_property("sub-text/ass-full", "")

    if subtitleLinesOnScreen == "" then return end

    subtitleLinesOnScreen = "\n"..subtitleLinesOnScreen

    for line in assline:lines(subtitleLinesOnScreen) do

        styles.onscreen[line.Style] = true
    end
end

local function loadUserStyles()

    for i = 1, 9 do

        if config["style"..i] ~= "" then

            local styleName = config["style"..i]:match("Name:([^,]*)")

            if styleName then

                table.insert(styles.user, {index = i, name = styleName})
            end
        end
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
    styles.user         = {}
    index.styles        = 1
    index.editstyle     = 1
    data                = {}
    map                 = {}
    page                = "styles"
    prevPage            = ""
    changed             = false
    resampleRes.dWidth  = 0
    resampleRes.dHeight = 0
    scrollOffset        = 1
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

local function applyUserStyle()

    local userStyle = config["style"..styles.user[index.userstyles].index]

    if userStyle == "" then return end

    local shouldResample = resampleRes.dWidth > 0 and resampleRes.dWidth ~= resampleRes.sWidth and resampleRes.dHeight > 0 and resampleRes.dHeight ~= resampleRes.sHeight
    userStyle            = userStyle:gsub("Name:[^,]*", "")

    for p, v in userStyle:gmatch("([^:,]+):([^:,]+)") do

        input.init()
        input.font_size = config.font_size

        if map[p] then

            map[p].setRange()

            v = map[p].getValue and map[p].getValue(v) or v

            if input.default(v) then

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
    end
end

local function toggle()

    if not opened then

        local overrideMode = mp.get_property("sub-ass-override", "")

        if not (overrideMode == "yes" or overrideMode == "scale") then mp.osd_message("Style override functionality only works with \"--sub-ass-override=yes\" or \"--sub-ass-override=scale\".", 3) return end

        local metadata = mp.get_property("sub-ass-extradata", "")

        if metadata == "" then mp.osd_message("Missing metadata! This is not an ASS file.", 3) return end

        resampleRes.dWidth, resampleRes.dHeight = assline:resolution(metadata)

        fillData()
        loadScreenStyles()
        loadUserStyles()

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
        setBindings()
    else

        writeToCache()
        unsetBindings()
        updateOverlay("", 0, 0)

        input.reset()
        reset()
        collectgarbage()
    end

    opened = not opened
end

local function switchPage(name)

    prevPage = page

    unsetBindings()

    page = name

    setBindings()
end

pages = {

    styles = {

        title = function()

            return string.format("{\\bord%s\\b1\\fs%s}[%s/%s] %s", data.borderSize, config.font_size, index.styles, #styles.original, "Styles")
        end,

        rows = function()

            local i = scrollOffset
            local n = 1

            return function()

                if not styles.original[i] or n > config.max_items then return nil end

                local columns   = {""}
                local styleName = styles.original[i].Name
                local edited    = styles.overrides[styleName]

                columns[1] = columns[1]..string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size)

                if styles.onscreen[styleName] then

                    columns[1] = columns[1]..string.format("{\\c%s}", colors.selected)
                end

                if i == index.styles then

                    columns[1] = columns[1]..string.format("{\\b1}● %s%s{\\b0}", edited and data.editedSymbol or "", styleName)
                else

                    columns[1] = columns[1]..string.format("○ %s%s", edited and data.editedSymbol or "", styleName)
                end

                i = i + 1
                n = n + 1

                return columns
            end
        end,

        hint = function()

            local hints = {}

            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s", data.borderSize, config.hint_font_size, "Navigation"))
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s%s", data.borderSize, config.hint_font_size, "<RIGHT> Edit", data.tab.."<UP-DOWN> Prev / Next Item"))
            table.insert(hints, "")
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s", data.borderSize, config.hint_font_size, "Actions"))
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s%s%s%s", data.borderSize, config.hint_font_size, "<DEL> Reset", data.tab.."<SHIFT+DEL> Reset all", data.tab.."<O> Load your style", data.tab.."<ESC> Exit"))
            table.insert(hints, "")
            table.insert(hints, string.format("{\\bord%s\\fs%s}%s", data.borderSize, config.hint_font_size, "Styles of the lines currently visible on screen will be highlighted in yellow."))

            local i = 1

            return function ()

                local h = hints[i]

                if not h then return nil end

                i = i + 1

                return h
            end
        end,

        bindings = function()

            local defaults = {

                close = {

                    key  = "esc",
                    func = function ()

                        toggle()
                    end,
                    opts = nil
                },

                previtem = {

                    key  = "up",
                    func = function ()

                        index.styles = math.max(index.styles - 1, 1)

                        local unvisible = scrollOffset - 1

                        if unvisible == index.styles then scrollOffset = scrollOffset - 1 end

                        render()
                    end,
                    opts = {repeatable = true}
                },

                nextitem = {

                    key  = "down",
                    func = function ()

                        index.styles = math.min(index.styles + 1, #styles.original)

                        local unvisible = scrollOffset + config.max_items

                        if unvisible == index.styles then scrollOffset = scrollOffset + 1 end

                        render()
                    end,
                    opts = {repeatable = true}
                },

                editstyle = {

                    key  = "right",
                    func = function ()

                        switchPage("editstyle")
                        render()
                    end,
                    opts = nil
                },

                userstyles = {

                    key  = "o",
                    func = function ()

                        local userStylesCount = #styles.user

                        if userStylesCount == 1 then

                            applyUserStyle()
                        elseif userStylesCount > 1 then

                            switchPage("userstyles")
                        end

                        render()
                    end,
                    opts = nil
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
                }
            }

            defaults["userstylesalt"] = {

                key  = "O",
                func = defaults["userstyles"].func,
                opts = defaults["userstyles"].opts
            }

            return defaults
        end
    },

    editstyle = {

        title = function()

            return string.format("{\\bord%s\\b1\\fs%s}← Edit style: \"%s\"", data.borderSize, config.font_size, styles.original[index.styles].Name)
        end,

        rows = function()

            local i         = 1
            local styleName = styles.original[index.styles].Name

            return function()

                if not styles.editable[i] then return nil end

                local columns  = {[1] = "", [2] = {}}
                local property = styles.editable[i]
                local edited   = styles.overrides[styleName] and styles.overrides[styleName][property]

                columns[1] = string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size)

                if i == index.editstyle then

                    columns[1] = columns[1]..string.format("{\\b1}● %s%s{\\b0}", edited and data.editedSymbol or "", data.propertyNames[property] or property)
                else

                    columns[1] = columns[1]..string.format("○ %s%s", edited and data.editedSymbol or "", data.propertyNames[property] or property)
                end

                if page == "editstyle" or (page == "editvalue" and i ~= index.editstyle) then

                    if edited then

                        table.insert(columns[2], string.format("{\\bord%s\\fs%s}%s", data.borderSize, config.font_size, styles.overrides[styleName][property]))
                    else

                        table.insert(columns[2], string.format("{\\bord%s\\fs%s}%s", data.borderSize, config.font_size, styles.original[index.styles][property]))
                    end
                else

                    local text, textWithCursor = input.texts()

                    table.insert(columns[2], text)
                    table.insert(columns[2], textWithCursor)
                end

                i = i + 1

                return columns
            end
        end,

        hint = function()

            local hints = {}

            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s", data.borderSize, config.hint_font_size, "Navigation"))
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s%s", data.borderSize, config.hint_font_size, "<LEFT-RIGHT> Back / Edit", data.tab.."<UP-DOWN> Prev / Next Item"))
            table.insert(hints, "")
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s", data.borderSize, config.hint_font_size, "Actions"))
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s%s%s%s%s", data.borderSize, config.hint_font_size, "<ENTER> Confirm", data.tab.."<DEL> Reset value", data.tab.."<SHIFT+DEL> Reset style", data.tab.."<O> Load your style", data.tab.."<ESC> Exit"))

            local i = 1

            return function ()

                local h = hints[i]

                if not h then return nil end

                i = i + 1

                return h
            end
        end,

        bindings = function()

            local defaults = {

                close = {

                    key  = "esc",
                    func = function ()

                        toggle()
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

                        switchPage("editvalue")
                        handleEdit()
                        render()
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

                userstyles = {

                    key  = "o",
                    func = function ()

                        local userStylesCount = #styles.user

                        if userStylesCount == 1 then

                            applyUserStyle()
                        elseif userStylesCount > 1 then

                            switchPage("userstyles")
                        end

                        render()
                    end,
                    opts = nil
                },

                back = {

                    key  = "left",
                    func = function ()

                        switchPage("styles")
                        render()
                    end,
                    opts = nil
                },

                disableenter = {

                    key  = "enter",
                    func = function ()

                    end,
                    opts = nil
                }
            }

            defaults["userstylesalt"] = {

                key  = "O",
                func = defaults["userstyles"].func,
                opts = defaults["userstyles"].opts
            }

            return defaults
        end
    },

    editvalue = {

        title = function()

            return pages.editstyle.title()
        end,

        rows = function()

            return pages.editstyle.rows()
        end,

        hint = function()

            return pages.editstyle.hint()
        end,

        bindings = function()

            local defaults = {

                close = {

                    key  = "esc",
                    func = function ()

                        switchPage("editstyle")
                        render()
                    end,
                    opts = nil
                },

                click = {

                    key  = "mbtn_left",
                    func = function ()

                        switchPage("editstyle")
                        render()
                    end,
                    opts = nil
                },

                confirm = {

                    key  = "enter",
                    func = function ()

                        switchPage("editstyle")
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
                        render()
                    end,
                    opts = {repeatable = true}
                },

                nextitem = {

                    key  = "down",
                    func = function ()

                        changeValue(input.get_text())
                        applyStyleOverrides()

                        index.editstyle = math.min(index.editstyle + 1, #styles.editable)

                        handleEdit()
                        render()
                    end,
                    opts = {repeatable = true}
                }
            }

            local inputs = input.bindings({

                after_changes = function()

                    render()
                end,

                edit_clipboard = function(text)

                    local property = styles.editable[index.editstyle]

                    if property and string.find(property, "Colour", 1, true) and #text == 6 then text = text..",00" end

                    return text
                end
            })

            return tableMerge(defaults, inputs)
        end
    },

    userstyles = {

        title = function()

            return string.format("{\\bord%s\\b1\\fs%s}%s", data.borderSize, config.font_size, "Your styles")
        end,

        rows = function()

            local i         = 1
            local styleName = styles.original[index.styles].Name

            return function()

                if not styles.user[i] then return nil end

                local columns = {""}

                columns[1] = columns[1]..string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size)

                if i == index.userstyles then

                    columns[1] = columns[1]..string.format("{\\b1}● %s{\\b0}", styles.user[i].name)
                else

                    columns[1] = columns[1]..string.format("○ %s", styles.user[i].name)
                end

                i = i + 1

                return columns
            end
        end,

        hint = function()

            local hints = {}

            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s", data.borderSize, config.hint_font_size, "Navigation"))
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s%s", data.borderSize, config.hint_font_size, "<LEFT> Back", data.tab.."<UP-DOWN> Prev / Next Item"))
            table.insert(hints, "")
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s", data.borderSize, config.hint_font_size, "Actions"))
            table.insert(hints, string.format("{\\bord%s\\b0\\fs%s}%s%s", data.borderSize, config.hint_font_size, "<ENTER> Apply", data.tab.."<ESC> Exit"))

            local i = 1

            return function ()

                local h = hints[i]

                if not h then return nil end

                i = i + 1

                return h
            end
        end,

        bindings = function()

            local defaults = {

                close = {

                    key  = "esc",
                    func = function ()

                        toggle()
                    end,
                    opts = nil
                },

                apply = {

                    key  = "enter",
                    func = function ()

                        applyUserStyle()
                        switchPage(prevPage)
                        render()
                    end,
                    opts = nil
                },

                back = {

                    key  = "left",
                    func = function ()

                        switchPage(prevPage)
                        render()
                    end,
                    opts = nil
                },

                previtem = {

                    key  = "up",
                    func = function ()

                        index.userstyles = math.max(index.userstyles - 1, 1)

                        render()
                    end,
                    opts = {repeatable = true}
                },

                nextitem = {

                    key  = "down",
                    func = function ()

                        index.userstyles = math.min(index.userstyles + 1, #styles.user)

                        render()
                    end,
                    opts = {repeatable = true}
                }
            }

            return defaults
        end
    }
}

function setBindings()

    for name, binding in pairs(pages[page].bindings()) do mp.add_forced_key_binding(binding.key, "stylesmanager_"..name, binding.func, binding.opts) end
end

function unsetBindings()

    for name in pairs(pages[page].bindings()) do mp.remove_key_binding("stylesmanager_"..name) end
end

mp.observe_property("osd-dimensions", "native", function (_, value)

    if opened then

        fillData()
        render()
    end
end)

mp.observe_property("sid", "number", function(_, value)

    if opened then toggle() end
end)

mp.register_event("file-loaded", function() readFromCache("overridefile/converted") end)

mp.add_key_binding(nil, "stylesmanager", toggle)