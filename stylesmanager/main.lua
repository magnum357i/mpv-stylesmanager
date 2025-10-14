--[[

╔════════════════════════════════╗
║        MPV stylesmanager       ║
║             v1.0.0             ║
╚════════════════════════════════╝

]]

local options = require 'mp.options'
local utils   = require "mp.utils"
local assline = require "assline"
local assdraw = require "mp.assdraw"
local input   = require "input"
local config  = {

    font_size      = 18,
    hint_font_size = 11,
    padding        = 20
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
    local configPath = os.getenv("APPDATA")
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
        "PrimaryColor", "OutlineColor", "ShadowColor",
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

    line = string.gsub(line, "Color=([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]),([0-9A-Fa-f][0-9A-Fa-f])", function(color, alpha)

            return string.format("Colour=&H%s%s&", alpha, convertColor(color, "RGB"))
    end)

    line = string.gsub(line, "(Scale[XY])=(%d+)", function(scale, val)

            return string.format("%s=%s", scale, val / 100)
    end)

    line = string.gsub(line, "Alignment=([4-9])", function(val)

        local alignments = {

            ["4"] = "9",
            ["5"] = "10",
            ["6"] = "11",
            ["7"] = "5",
            ["8"] = "6",
            ["9"] = "7"
        }

        return string.format("Alignment=%s", alignments[val])
    end)

    return line
end

local function getStyleOverrides()

    local overrides = {}

    for i, v in pairs(styles.overrides) do

        table.insert(overrides, lastChanges(serializeStyle(styles.original[tonumber(i)].Name, v)))
    end

    if #overrides == 0 then return "" end

    return table.concat(overrides, ",")
end

local function setStyleOverrides()

    local overrides = getStyleOverrides()

    if overrides == "" then return end

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

        PrimaryColor = {

            setRange = function()

                input.format = "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f],[0-9A-Fa-f][0-9A-Fa-f]"
            end,

            getValue = function (v)

                local alpha, color = v:match("([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])")

                if not alpha then return string.format("%s,%s", "000000", "00") end

                return string.format("%s,%s", convertColor(color, "BGR"), alpha)
            end
        },

        OutlineColor = {

            setRange = function()

                input.format = "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f],[0-9A-Fa-f][0-9A-Fa-f]"
            end,

            getValue = function (v)

                local alpha, color = v:match("([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])")

                if not alpha then return string.format("%s,%s", "000000", "00") end

                return string.format("%s,%s", convertColor(color, "BGR"), alpha)
            end
        },

        ShadowColor = {

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

    ass:new_event()
    ass:an(7)
    ass:pos(config.padding, lineY)
    ass:append(string.format("{\\bord%s\\b0\\fs%s}", data.borderSize, config.hint_font_size))
    ass:append(string.format("%s"..data.tab.."%s"..data.tab.."%s"..data.tab.."%s"..data.tab.."%s", "<LEFT-RIGHT> Back / Edit", "<UP-DOWN> Prev / Next Item", "<ENTER> Confirm", "<DEL> Revert to default", "<ESC> Exit"))

    lineY = lineY + config.hint_font_size + config.padding

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

        ass:new_event()
        ass:an(7)
        ass:pos(config.padding, lineY + config.padding)
        ass:append(string.format("{\\bord%s\\fs%s}", data.borderSize, config.hint_font_size))
        ass:append("Styles of the lines currently visible on screen will be highlighted in yellow.")
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

                ass:append(string.format("{\\b1}● %s%s{\\b0}", editedSymbol, name))
            else

                ass:append(string.format("○ %s%s", editedSymbol, name))
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

    --update

    updateOverlay(ass.text)
end

local function handleEdit()

    local property = styles.editable[index.editstyle]

    input.init()

    input.theme     = "black"
    input.font_size = config.font_size

    if map[property] then map[property].setRange() end

    if styles.overrides[tostring(index.styles)] and styles.overrides[tostring(index.styles)][property] then

        input.default(tostring(styles.overrides[tostring(index.styles)][property]))
    else

        input.default(tostring(styles.original[index.styles][property]))
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

    if next(styles.overrides) == nil then return end

    local file

    file = io.open(getPath("overridefile"), "w")

    if not file then mp.osd_message("Config file not created!") return end

    file:write(utils.format_json(styles.overrides))
    file:close()

    local overrides = getStyleOverrides()

    if overrides == "" then return end

    file = io.open(getPath("overridefile/converted"), "w")

    if not file then mp.osd_message("Config file not created!") return end

    file:write(overrides)
    file:close()
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

                    saveConfig()
                    toggle("styles")
                end,
                opts = nil
            },

            nextitem = {

                key  = "down",
                func = function ()

                    index.styles = math.min(index.styles + 1, #styles.original)

                    render()
                end,
                opts = {repeatable = true}
            },

            previtem = {

                key  = "up",
                func = function ()

                    index.styles = math.max(index.styles - 1, 1)

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

                    saveConfig()
                    toggle("editstyle")
                end,
                opts = nil
            },

            nextitem = {

                key  = "down",
                func = function ()

                    index.editstyle = math.min(index.editstyle + 1, #styles.editable)

                    render()
                end,
                opts = {repeatable = true}
            },

            previtem = {

                key  = "up",
                func = function ()

                    index.editstyle = math.max(index.editstyle - 1, 1)

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
                opts = {repeatable = true}
            },

            revertdefault = {

                key  = "del",
                func = function ()

                    local property = styles.editable[index.editstyle]

                    if styles.overrides[tostring(index.styles)] and styles.overrides[tostring(index.styles)][property] then

                        styles.overrides[tostring(index.styles)][property] = nil

                        setStyleOverrides()
                        render()
                    end
                end,
                opts = {repeatable = true}
            },

            backstyles = {

                key  = "left",
                func = function ()

                    page = "styles"

                    unsetBindings("editstyle")
                    setBindings("styles")

                    render()
                end,
                opts = {repeatable = true}
            },

            disableenter = {

                key  = "enter",
                func = function ()

                end,
                opts = nil
            },
        }
    elseif section == "editvalue" then

        inputBindings = input.bindings({

            after_changes = function()

                render()
            end,
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

                    local property = styles.editable[index.editstyle]

                    if not styles.overrides[tostring(index.styles)] then styles.overrides[tostring(index.styles)] = {} end

                    if tostring(styles.original[index.styles][property]) == input.get_text() then

                        styles.overrides[tostring(index.styles)][property] = nil
                    else

                        styles.overrides[tostring(index.styles)][property] = (map[property] and map[property].setValue) and map[property].setValue(input.get_text()) or input.get_text()
                    end

                    setStyleOverrides()
                    render()
                end,
                opts = nil
            },

            disabledown = {

                key  = "down",
                func = function ()

                end,
                opts = {repeatable = true}
            },

            disableup = {

                key  = "up",
                func = function ()

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

mp.register_event("file-loaded", function() readConfig("overridefile/converted") end)

mp.add_key_binding(nil, "stylesmanager", function() toggle("styles") end)