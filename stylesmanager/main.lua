--[[

╔════════════════════════════════╗
║        MPV stylesmanager       ║
║             v1.0.2             ║
╚════════════════════════════════╝

]]

local options = require 'mp.options'
local utils   = require "mp.utils"
local assdraw = require "mp.assdraw"
local assline = require "assline"
local input   = require "input"
local config  = {

    font_size      = 18,
    hint_font_size = 11,
    padding        = 20,
    my_style       = ""
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

    local fullPath
    local hash       = hash(utils.split_path(mp.get_property("path")))
    local configPath = os.getenv("temp")
    local configDir  = "mpvstylesmanager"
    local seperator  = "\\"

    if key == "config" then

        fullPath = utils.join_path(configPath, configDir)
    elseif key == "overridefile" then

        fullPath = utils.join_path(configPath, configDir..seperator..hash..".json")
    elseif key == "overridefile/converted" then

        fullPath = utils.join_path(configPath, configDir..seperator..hash..".converted.json")
    end

    return fullPath
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

local function calculateTextWidth(text, fontSize)

    textOverlay.res_x, textOverlay.res_y = mp.get_osd_size()
    textOverlay.data                     = "{\\bord0\\b0\\fs"..fontSize.."}"..text
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

local function fillData()

    data.screenWidth, data.screenHeight = mp.get_osd_size()
    data.borderSize                     = mp.get_property_number('osd-border-size')
    data.columns                        = {10, calculateTextWidth(string.rep("A", 13), config.font_size)}
    data.tab                            = string.rep("\\h", 4)
    data.propertyNames                  = {

        Fontname      = "Font",
        Fontsize      = "Size",
        PrimaryColour = "Color",
        OutlineColour = "Border Color",
        BackColour    = "Shadow Color",
        ScaleX        = "Scale X",
        ScaleY        = "Scale Y",
        Outline       = "Border",
        Alignment     = "Position",
        MarginV       = "Vertical Align",
        MarginL       = "Left Align",
        MarginR       = "Right Align"
    }
end

local function setStyles(metadata)

    if #styles.original > 0 then return end

    for style in metadata:gmatch("Style:[^\n]+") do

        style = assline:new(style)

        if style then

            for _, name in pairs(styles.editable) do

                if map[name] and map[name].getValue and style[name] ~= nil then

                    style[name] = map[name].getValue(style[name])
                end
            end

            table.insert(styles.original, style)
        end
    end
end

local function getEditableValues()

    return {

        "Fontname", "Fontsize",
        "PrimaryColour", "OutlineColour", "BackColour",
        "Bold", "Italic",
        "ScaleX", "ScaleY", "Spacing",
        "Outline", "Shadow",
        "Alignment", "MarginV", "MarginR", "MarginL"
    }
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

    line = string.gsub(line, "(Alignment)=([4-9])", function(p, val)

        local alignments = {

            ["4"] = "9",
            ["5"] = "10",
            ["6"] = "11",
            ["7"] = "5",
            ["8"] = "6",
            ["9"] = "7"
        }

        return string.format("%s=%s", p, alignments[val])
    end)

    return line
end

local function getStyleOverrides()

    local overrides = {}

    for i, v in pairs(styles.overrides) do

        v = serializeStyle(styles.original[tonumber(i)].Name, v)

        if v ~= "" then table.insert(overrides, lastChanges(v)) end
    end

    if #overrides == 0 then return "" end

    return table.concat(overrides, ",")
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

                input.max = 50
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

                if not v then return 1 end

                return v
            end
        },

        Bold = {

            setRange = function()

                input.accept_only = "int"
                input.min         = 0
                input.max         = 1
            end,

            getValue = function (v)

                return v and "1" or "0"
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

                return v and "1" or "0"
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

                if not v then return 0 end

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

                if not v then return 0 end

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
            end
        },

        Outline = {

            setRange = function()

                input.accept_only = "float"
                input.min         = 0
                input.max         = 50
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
            end
        },

        Shadow = {

            setRange = function()

                input.accept_only = "float"
                input.min         = 0
                input.max         = 50
            end,

            setValue = function (v)

                v = tonumber(v)

                if not v then return 0 end

                return v
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
        ass:append(string.format("(%s) Styles", #styles.original))

        lineY = lineY + config.font_size

        for i = 1, #styles.original do

            ass:new_event()
            ass:an(7)
            ass:pos(config.padding + data.columns[1], lineY)
            ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size))

            if styles.onscreen[styles.original[i].Name] then

                ass:append(string.format("{\\c%s}", colors.selected))
            end

            if i == index.styles then

                ass:append(string.format("{\\b1}● %s{\\b0}", styles.original[i].Name))
            else

                ass:append(string.format("○ %s", styles.original[i].Name))
            end

            lineY = lineY + config.font_size
        end
    elseif page == "editstyle" or page == "editvalue" then

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY)
        ass:append(string.format("{\\bord%s\\b1\\fs%s}", data.borderSize, config.font_size))
        ass:append(string.format("← Edit style: \"%s\"", styles.original[index.styles].Name))

        lineY = lineY + config.font_size

        for i, name in pairs(styles.editable) do

            local override = styles.overrides[tostring(index.styles)] and styles.overrides[tostring(index.styles)][name]
            local editedSymbol   = ""

            ass:new_event()
            ass:an(7)
            ass:pos(config.padding + data.columns[1], lineY)
            ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size))

            if override and styles.overrides[tostring(index.styles)][name] ~= styles.original[index.styles][name] then editedSymbol = "*" end

            if i == index.editstyle then

                ass:append(string.format("{\\b1}● %s%s{\\b0}", editedSymbol, data.propertyNames[name] or name))
            else

                ass:append(string.format("○ %s%s", editedSymbol, data.propertyNames[name] or name))
            end

            if page == "editstyle" or (page == "editvalue" and i ~= index.editstyle) then

                ass:new_event()
                ass:an(7)
                ass:pos(config.padding + data.columns[2], lineY)
                ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.font_size))

                if override then

                    ass:append(styles.overrides[tostring(index.styles)][name])
                else

                    ass:append(styles.original[index.styles][name])
                end
            else

                local text, textWithCursor = input.texts()

                --[[
                local editBarWidth         = calculateTextWidth(text, config.font_size) + config.padding * 2

                ass:new_event()
                ass:an(7)
                ass:pos(config.padding + data.columns[2], lineY)
                ass:append(string.format("{\\bord0\\1c&H%s&\\1a&H%x&}", "FFFFFF", 0))
                ass:draw_start()
                ass:round_rect_cw(0, 0, editBarWidth, config.font_size, 0, 0)
                ass:draw_stop()
                ]]

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

    lineY = lineY + config.hint_font_size * 1.5

    ass:new_event()
    ass:an(7)
    ass:pos(config.padding, lineY)
    ass:append(string.format("{\\bord%s\\b0\\fs%s}", data.borderSize, config.hint_font_size))
    ass:append(string.format("%s"..data.tab.."%s"..data.tab.."%s"..data.tab.."%s"..data.tab.."%s", "<ENTER> Confirm", "<DEL> Reset value", "<SHIFT+DEL> Reset all", "<O> Load your style", "<ESC> Exit"))

    if page == "styles" then

        lineY = lineY + config.hint_font_size + config.padding

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY)
        ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.hint_font_size))
        ass:append("Styles of the lines currently visible on screen will be highlighted in yellow.")
    end

    --update

    updateOverlay(ass.text)
end

local function handleEdit()

    local p = styles.editable[index.editstyle]
    local i = tostring(index.styles)

    input.init()

    input.theme     = "black"
    input.font_size = config.font_size

    if map[p] then map[p].setRange() end

    if styles.overrides[i] and styles.overrides[i][p] then

        input.default(tostring(styles.overrides[i][p]))
    else

        input.default(tostring(styles.original[tonumber(i)][p]))
    end

    unsetBindings("editstyle")
    setBindings("editvalue")

    render()
end

local function setScreenStyles()

    if next(styles.onscreen) ~= nil then return end

    local subtitleLinesOnScreen = mp.get_property("sub-text/ass-full", "")

    if subtitleLinesOnScreen == "" then return end

    for line in subtitleLinesOnScreen:gmatch("Dialogue:[^\n]+") do

        line = assline:new(line)

        if line then

            styles.onscreen[line.Style] = true
        end
    end
end

local function changeValue(newValue, property)

    local p = property or styles.editable[index.editstyle]
    local i = tostring(index.styles)

    if newValue ~= nil then

        if not styles.overrides[i] then styles.overrides[i] = {} end

        if tostring(styles.original[index.styles][p]) == newValue then

            styles.overrides[i][p] = nil
        else

            styles.overrides[i][p] = (map[p] and map[p].setValue) and map[p].setValue(newValue) or newValue
        end
    else

        if styles.overrides[i] and styles.overrides[i][p] then

            styles.overrides[i][p] = nil

            if next(styles.overrides[i]) == nil then styles.overrides[i] = nil end
        end
    end
end

local function reset()

    styles.original  = {}
    styles.overrides = {}
    styles.onscreen  = {}
    styles.editable  = {}
    index.styles     = 1
    index.editstyle  = 1
    data             = {}
    map              = {}
    page             = "styles"
end

local function saveConfig()

    local configPath = getPath("config")

    if not os.rename(configPath, configPath) then

        runCommand({"powershell", "-NoProfile", "-Command", "mkdir", configPath})
    end

    local file
    local formattedOverrides = getStyleOverrides()

    if formattedOverrides == "" then

        for _, k in pairs({"overridefile", "overridefile/converted"}) do

            file = io.open(getPath(k), "r")

            if file then

                file:close()

                os.remove(getPath(k))
            end
        end

        return
    end

    for _, k in pairs({"overridefile", "overridefile/converted"}) do

        file = io.open(getPath(k), "w")

        if not file then

            mp.osd_message("Config file not created!")
        else

            file:write(k == "overridefile" and utils.format_json(styles.overrides) or formattedOverrides)
            file:close()
        end
    end
end

local function readConfig(fileType)

    local file

    if fileType == "overridefile" then

        local file = io.open(getPath(fileType), "r")

        if not file then return end

        local content = file:read("*all")

        file:close()

        styles.overrides = utils.parse_json(content)
    elseif fileType == "overridefile/converted" then

        local file = io.open(getPath(fileType), "r")

        if not file then return end

        local content = file:read("*all")

        file:close()

        mp.set_property("sub-ass-style-overrides", content)
    end
end

local function toggle(section)

    if not opened then

        local metadata = mp.get_property("sub-ass-extradata", "")

        if metadata == "" then mp.osd_message("No style data found.", 3) return end

        fillData()
        setScreenStyles()

        map             = generateMap()
        styles.editable = getEditableValues()

        setStyles(metadata)

        if #styles.original == 0 then

            reset()
            collectgarbage()

            mp.osd_message("No styles found.", 3)

            return
        end

        readConfig("overridefile")
        render()
        setBindings(section)
    else

        saveConfig()
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

            disabledel = {

                key  = "del",
                func = function ()

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

                    changeValue(nil)
                    applyStyleOverrides()
                    render()
                end,
                opts = nil
            },

            resetall = {

                key  = "shift+del",
                func = function ()

                    styles.overrides[tostring(index.styles)] = nil

                    applyStyleOverrides()
                    render()
                end,
                opts = nil
            },

            loadefaultstyle = {

                key  = "o",
                func = function ()

                    if config.my_style == "" then return end

                    local changed = false

                    for p, v in config.my_style:gmatch("([^:,]+):([^:,]+)") do

                        input.init()

                        input.font_size = config.font_size

                        if map[p] then

                            map[p].setRange()

                            v = map[p].getValue and map[p].getValue(v) or v

                            if input.default(v) then

                                changed = true

                                changeValue(input.get_text(), p)
                            else

                                mp.msg.warn(string.format("Value is out of allowed range: %s (%s)", v, p))
                            end
                        else

                            mp.msg.warn(string.format("This property has no defined handler: %s", p))
                        end
                    end

                    if changed then

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

    for name, binding in pairs(bindingList(section)) do mp.add_forced_key_binding(binding.key, "stylemanager_"..name, binding.func, binding.opts) end
end

function unsetBindings(section)

    for name in pairs(bindingList(section)) do mp.remove_key_binding("stylemanager_"..name) end
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

mp.register_event("file-loaded", function() readConfig("overridefile/converted") end)

mp.add_key_binding(nil, "stylesmanager", function() toggle(page) end)