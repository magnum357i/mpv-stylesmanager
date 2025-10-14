--v1.5
local utf8  = require "fastutf8"
local input = {}
local cursor, text, s_width, s_height, b_width, cached

local text_overlay          = mp.create_osd_overlay("ass-events")
text_overlay.compute_bounds = true
text_overlay.hidden         = true

local function build_lines(pre_c, post_c, o)

    return
    string.format("{\\bord0\\c&H%s&\\fs%s}", input.theme == "black" and "000000" or "FFFFFF", input.font_size)..pre_c..post_c,
    string.format("{\\bord0\\alpha&HFF&\\fs%s}", input.font_size)..pre_c..string.format("{\\alpha&H00&\\p1\\c&H%s&}m 0 0 l 1 0 l 1 %s l 0 %s{\\p0\\alpha&HFF&}", input.theme == "black" and "000000" or "FFFFFF", input.font_size, input.font_size)..post_c,
    o
end

local function validate(str)

    if input.format ~= "" then

        return str:find("^"..input.format.."$")
    elseif input.accept_only == "int" then

        if str == "00" then return false end

        if str == "-" and string.find(tostring(input.min), "%-") then return true end

        if str:find("%.") then return false end

        str = tonumber(str)

        if not str then return false end

        return str >= input.min and str <= input.max
    elseif input.accept_only == "float" then

        if str == "00" then return false end

        if str == "-" and string.find(tostring(input.min), "%-") then return true end

        str = tonumber(str)

        if not str then return false end

        local wholeP, fracP = string.match(tostring(str), "^(%-?%d+)%.?(%d*)$")

        if tonumber(fracP) and utf8.len(fracP) > input.decimal then return false end

        return str >= input.min and str <= input.max
    end

    local count = utf8.len(str)

    return count <= input.max
end

local function get_text_width(text)

    text_overlay.res_x, text_overlay.res_y = s_width, s_height
    text_overlay.data                      = "{\\fs"..input.font_size.."}"..text
    local res                              = text_overlay:update()

    return (res and res.x1) and (res.x1 - res.x0) or 0
end

local function get_clipboard()

    local clipboard = mp.get_property("clipboard/text", "")
    clipboard       = clipboard:gsub("^%s*(.-)%s*$", "%1")

    return clipboard
end

function input.get_text()

    return text
end

function input.texts()

    if text == "" then return "", string.format("{\\bord0\\p1\\c&H%s&}m 0 0 l 1 0 l 1 %s l 0 %s", input.theme == "black" and "000000" or "FFFFFF", input.font_size, input.font_size), 0 end

    if cached.text and (cached.text == text and cached.cursor == cursor) then return build_lines(cached.pre_cursor, cached.post_cursor, cached.offset) end

    local pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
    local post_cursor = utf8.sub(text, cursor + 1, 0)
    local offset      = 0

    if s_width > 0 and s_height > 0 and b_width > 0 then

        local pre_cursor_width  = get_text_width(pre_cursor)
        local search_text_width = get_text_width(pre_cursor..post_cursor)

        offset = search_text_width > b_width and math.max(0, math.min(pre_cursor_width - b_width / 2, search_text_width - b_width)) or 0
    end

    cached.text        = text
    cached.cursor      = cursor
    cached.pre_cursor  = pre_cursor
    cached.post_cursor = post_cursor
    cached.offset      = offset

    return build_lines(pre_cursor, post_cursor, offset)
end

function input.calculate_offset(width, height, bar_width)

    s_width  = width
    s_height = height
    b_width  = bar_width
end

--after_changes, edit_clipboard(text)
function input.bindings(hooks)

    local list = {

        cursorhome = {

            key  = "home",
            func = function ()

                cursor = 0

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = nil
        },

        cursorend = {

            key  = "end",
            func = function ()

                cursor = utf8.len(text)

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = nil
        },

        cursorleft = {
            key  = "left",
            func = function ()

                if text ~= "" and input.format ~= "" and cursor > 0 and string.find(utf8.sub(text, cursor, cursor), "%p") then

                    cursor = cursor - 1
                end

                cursor = cursor - 1
                cursor = math.max(cursor, 0)

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        cursorright = {

            key  = "right",
            func = function ()

                local count = utf8.len(text)
                cursor      = cursor + 1

                if text ~= "" and input.format ~= "" and string.find(utf8.sub(text, cursor + 1, cursor + 1), "%p") then

                    cursor = cursor + 1
                end

                cursor = math.min(cursor, count)

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        paste = {

            key  = "ctrl+v",
            func = function ()

                local clipboard_text = get_clipboard()

                if input.format ~= "" or input.accept_only ~= "" then

                    if hooks and hooks.edit_clipboard then clipboard_text = hooks.edit_clipboard(clipboard_text) end

                    if not validate(clipboard_text) then return end

                    text   = clipboard_text
                    cursor = utf8.len(text)

                    if hooks and hooks.after_changes then hooks.after_changes() end

                    return
                end

                local count = utf8.len(text)

                if count >= input.max then return end

                local pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                local post_cursor = utf8.sub(text, cursor + 1, 0)
                clipboard_text    = utf8.sub(clipboard_text, 1, input.max - count)
                text              = pre_cursor..clipboard_text..post_cursor
                cursor            = cursor + utf8.len(clipboard_text)

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        deletebackward = {

            key  = "bs",
            func = function ()

                if input.format ~= "" or cursor == 0 then return end

                cursor            = cursor - 1
                cursor            = math.max(cursor, 0)
                local pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                local post_cursor = utf8.sub(text, cursor + 2, 0)
                text              = pre_cursor..post_cursor

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        deleteforward = {

            key  = "del",
            func = function ()

                if input.format ~= "" then return end

                local count = utf8.len(text)

                if count == cursor then return end

                local pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                local post_cursor = utf8.sub(text, cursor + 2, 0)
                text              = pre_cursor..post_cursor

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        input = {

            key  = "any_unicode",
            func = function (info)

                if info.key_text and (info.event == "press" or info.event == "down" or info.event == "repeat") then

                    local pre_cursor, post_cursor

                    if input.format == "" then

                        pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                        post_cursor = utf8.sub(text, cursor + 1, 0)
                    else

                        pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                        post_cursor = utf8.sub(text, cursor + 2, 0)
                    end

                    local tempText = pre_cursor..info.key_text..post_cursor

                    if not validate(tempText) then return end

                    text   = tempText
                    cursor = cursor + 1

                    if input.format ~= "" and string.find(utf8.sub(text, cursor + 1, cursor + 1), "%p") then

                        cursor = cursor + 1
                    end

                    if hooks and hooks.after_changes then hooks.after_changes() end
                end
            end,
            opts = {repeatable = true, complex = true}
        }

    }

    return list
end

function input.default(str)

    if not validate(str) then print("Default value does not match the required format.") return end

    text   = str
    cursor = utf8.len(text)
end

function input.reset()

    input.theme          = "black"  --black,white
    input.font_size      = 0
    input.max            = 255
    input.min            = 0
    input.format         = ""       --regex
    input.accept_only    = ""       --int,float
    input.decimal        = 1
    cursor               = 0
    s_width              = 0
    s_height             = 0
    b_width              = 0
    cached               = {}
end

function input.init()

    text = ""

    input.reset()
end

return input