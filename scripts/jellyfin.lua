local opt = require 'mp.options'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local is_windows = package.config:sub(1,1) == '\\'

package.path = mp.command_native({"expand-path", "~~/script-modules/?.lua;"})..package.path
local input_success, input = pcall(require, "user-input-module")

local options = {
    url = "",
    username = "",
    password = "",
    image_path = "",
    hide_images = "",
    hide_spoilers = "on",
    show_by_default = "",
    show_on_idle = "",
    use_playlist = "",
    colour_default = "FFFFFF",
    colour_selected = "FF",
    colour_watched = "A0A0A0"
}
opt.read_options(options, mp.get_script_name())

local overlay = mp.create_osd_overlay("ass-events")
local meta_overlay = mp.create_osd_overlay("ass-events")
local shown = false
local user_id = ""
local api_key = ""
local user_query = ""

local parent_id = {"", "", "", ""}
local selection = {1, 1, 1, 1}
local list_start = {1, 1, 1, 1}
local layer = 1

local items = {}
local ow, oh, op = 0, 0, 0
local async = {} -- 1 = image thread, 2 = request thread

local align_x = 1 -- 1 = left, 2 = center, 3 = right
local align_y = 4 -- 4 = top, 8 = center, 0 = bottom
--A value of 1 specifies a left-justified subtitle
--A value of 2 specifies a centered subtitle
--A value of 3 specifies a right-justified subtitle
--Adding 4 to the value specifies a "Toptitle"
--Adding 8 to the value specifies a "Midtitle"
local align_main = "{\\a0}"
local align_other = "{\\a7}"

local toggle_overlay -- function
local move_up -- function
local move_right -- function
local move_down -- function
local move_left -- function

local function mkdir(path)
    if is_windows then
        --io.popen('mkdir "'..path..'"')
    else
        os.execute('mkdir -p "'..path..'"')
    end
end

local function send_request(method, url)
    if #api_key > 0 then
        local request = mp.command_native({
            name = "subprocess",
            capture_stdout = true,
            capture_stderr = true,
            playback_only = false,
            args = {"curl", "-X", method, url, "-H", "Authorization: MediaBrowser Token=\""..api_key.."\""}
        })
        return utils.parse_json(request.stdout)
    end
    return nil
end

local function clear_request(success, result, error)
    async[2] = nil
end

local function send_request_async(method, url)
    if #api_key > 0 and async[2] == nil then -- multiple requests are just discarded
        async[2] = mp.command_native_async({
            name = "subprocess",
            playback_only = false,
            args = {"curl", "-X", method, url, "-H", "Authorization: MediaBrowser Token=\""..api_key.."\""}
        }, function(success, result, error) clear_request(success, result, error) end)
        return 0
    end
    return 1
end

local function line_break(str, flags, space)
    if str == nil then return "" end
    local text = flags
    local n = 0
    for i = 1, #str do
        local c = str:sub(i, i)
        if (c == ' ' and i-n > space) or c == '\n' then
            text = text..str:sub(n, i-1).."\n"..flags
            n = i+1
        end
    end
    text = text..str:sub(n, -1)
    return text
end

local function update_list()
    overlay.data = ""
    local magic_num = 29 -- const
    if selection[layer] - list_start[layer] > magic_num then
        list_start[layer] = selection[layer] - magic_num
    elseif selection[layer] - list_start[layer] < 0 then
        list_start[layer] = selection[layer]
    end
    for i=list_start[layer],list_start[layer]+magic_num do
        if i > #items then break end
        local index = ""
        -- handles multi-part episodes
        local new_items = {}
        local part_count = 1
        local base_name = ""
        if items[i].PartCount ~= nil then part_count = items[i].PartCount end
        items[i].PartCount = 1
        if part_count > 1 then
            local part_url = options.url.."/Videos/"..items[i].Id.."/AdditionalParts"
            new_items = send_request("GET", part_url).Items
            base_name = items[i].Name
            items[i].Name = base_name.." (Part 1)"
        end
        for j=1,part_count-1 do
            table.insert(items, i+j, {})
            for k,v in pairs(items[i]) do --copy whole entry
                items[i+j][k] = v
            end
            items[i+j].Id = new_items[j].Id
            items[i+j].Name = base_name.." (Part "..(j+1)..")"
        end
        --
        if items[i].IndexNumber and items[i].IsFolder == false then
            index = items[i].IndexNumber..". "
        else
            -- nothing
        end
        overlay.data = overlay.data.."{\\fs16}".."{\\c&H"
        if i == selection[layer] then
            overlay.data = overlay.data..options.colour_selected
        elseif items[i].UserData.Played == true then
            overlay.data = overlay.data..options.colour_watched
        else
            overlay.data = overlay.data..options.colour_default
        end
        overlay.data = overlay.data.."&}"..index..items[i].Name.."\n"
    end
    overlay:update()
end

local scale = 2 -- const

local function show_image(success, result, error, userdata)
    if not success then
        msg.error("Failed to create image: " .. error)
        return
    elseif result.error_string == "init" then
        msg.error("Failed to create image: mpv not found.")
        return
    elseif result.status ~= 0 then
        if not result.killed_by_us then
            msg.error("Failed to create image: mpv exited with status: " .. result.status .. ".")
        end
        return
    end
    local x = (align_x == 3) and math.floor(ow/3.5) or math.floor(ow/2.5)
    local y = (align_y == 0) and oh-10-(userdata[2]*scale) or 10
    if shown == true then
        mp.command_native({
            name = "overlay-add",
            id = 0,
            x = x,
            y = y,
            file = userdata[3],
            offset = 0,
            fmt = "bgra",
            w = userdata[1],
            h = userdata[2],
            stride = userdata[1]*4,
            dw = userdata[1]*scale,
            dh = userdata[2]*scale
        })
    end
end

local function update_image(item)
    local width = math.floor(ow/(3*scale))
    local height = 0
    local filepath = ""
    if async[1] ~= nil then mp.abort_async_command(async[1]) end
    mp.commandv("overlay-remove", "0")
    if item.ImageTags.Primary ~= nil then
        height = math.floor(width/item.PrimaryImageAspectRatio)
        filepath = options.image_path.."/"..item.Id.."_"..width.."_"..height..".bgra"
        async[1] = mp.command_native_async({
            name = "subprocess",
            playback_only = false,
            args = { "mpv", options.url.."/Items/"..item.Id.."/Images/Primary?width="..width.."&height="..height, "--no-config", "--msg-level=all=no", "--vf=lavfi=[format=bgra]", "--of=rawvideo", "--o="..filepath }
        }, function(success, result, error) show_image(success, result, error, {width, height, filepath}) end)
    end
end

local function update_metadata(item)
    meta_overlay.data = ""
    local name = line_break(item.Name, align_other.."{\\fs24}", 30)
    meta_overlay.data = meta_overlay.data..name.."\n"
    local year = ""
    if item.ProductionYear then year = item.ProductionYear end
    local time = ""
    if item.RunTimeTicks then time = "   "..math.floor(item.RunTimeTicks/600000000).."m" end
    local rating = ""
    if item.CommunityRating then rating = "   "..item.CommunityRating end
    local hidden = ""
    local watched = ""
    if item.UserData.Played == false then
        if options.hide_spoilers ~= "off" then hidden = "{\\bord0}{\\1a&HFF&}" end
    else
        watched = "   Watched"
    end
    local favourite = ""
    if item.UserData.IsFavorite == true then
        favourite = "   Favorite"
    end
    meta_overlay.data = meta_overlay.data..align_other.."{\\fs16}"..year..time..rating..watched..favourite.."\n\n"
    local tagline = line_break(item.Taglines[1], align_other.."{\\fs20}", 35)
    meta_overlay.data = meta_overlay.data..tagline.."\n"
    local description = line_break(item.Overview, align_other.."{\\fs16}"..hidden, 45)
    meta_overlay.data = meta_overlay.data..description
    meta_overlay:update()
end

local function update_data()
    update_list()
    local item = items[selection[layer]]
    if options.hide_images ~= "on" then update_image(item) end
    update_metadata(item)
end

local function update_overlay()
    overlay.data = "{\\fs16}Loading..."
    overlay:update()
    local base_url = options.url.."/Items?userID="..user_id.."&parentId="..parent_id[layer].."&enableImageTypes=Primary&imageTypeLimit=1&fields=PrimaryImageAspectRatio,Taglines,Overview"
    if layer == 2 then
        base_url = base_url.."&sortBy=SortName"
    else
        -- nothing
    end
    local url = base_url.."&searchTerm="..user_query
    local json = send_request("GET", url)
    if json == nil or #json.Items == 0 then --no results
        items = send_request("GET", base_url).Items
    else
        items = json.Items
    end
    update_data()
end

local function width_change(name, data)
    ow, oh, op = mp.get_osd_size()
    if shown then update_image(items[selection[layer]]) end
end

local function play_video()
    toggle_overlay()
    mp.commandv("playlist-play-index", "none")
    mp.command("playlist-clear")
    if options.use_playlist == "on" then
        for i = 1, #items do
            if i ~= selection[layer] then
                mp.commandv("loadfile", options.url.."/Videos/"..items[i].Id.."/stream?static=true", "append")
            end
        end
    end
    mp.commandv("loadfile", options.url.."/Videos/"..items[selection[layer]].Id.."/stream?static=true", "insert-at-play", selection[layer]-1)
    mp.set_property("force-media-title", items[selection[layer]].Name)
end

move_up = function()
    if #items > 1 then
        selection[layer] = selection[layer] - 1
        if selection[layer] == 0 then selection[layer] = #items end
        update_data()
    end
end

local function key_up()
    if align_y == 0 then
        move_down()
    else
        move_up()
    end
end

move_right = function()
    if items[selection[layer]].IsFolder == false then
        play_video()
    else
        layer = layer + 1 -- shouldn't get too big
        parent_id[layer] = items[selection[layer-1]].Id
        selection[layer] = 1
        user_query = ""
        update_overlay()
    end
end

local function key_right()
    if align_x == 3 then
        move_left()
    else
        move_right()
    end
end

move_down = function()
    if #items > 1 then
        selection[layer] = selection[layer] + 1
        if selection[layer] > #items then selection[layer] = 1 end
        update_data()
    end
end

local function key_down()
    if align_y == 0 then
        move_up()
    else
        move_down()
    end
end

move_left = function()
    if layer == 1 then return end
    layer = layer - 1
    user_query = ""
    update_overlay()
end

local function key_left()
    if align_x == 3 then
        move_right()
    else
        move_left()
    end
end

local function connect()
    local request = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
        args = {"curl", options.url.."/Users/AuthenticateByName", "-H", "accept: application/json", "-H", "content-type: application/json", "-H", "x-emby-authorization: MediaBrowser Client=\"Custom Client\", Device=\"Custom Device\", DeviceId=\"1\", Version=\"0.0.1\"", "-d", "{\"username\":\""..options.username.."\",\"Pw\":\""..options.password.."\"}"}
    })
    local result = utils.parse_json(request.stdout)
    user_id = result.User.Id
    api_key = result.AccessToken
end

toggle_overlay = function()
    if shown then
        mp.remove_key_binding("jup")
        mp.remove_key_binding("jright")
        mp.remove_key_binding("jdown")
        mp.remove_key_binding("jleft")
        mp.commandv("overlay-remove", "0")
        overlay:remove()
        meta_overlay:remove()
    else
        mp.add_forced_key_binding("UP", "jup", key_up, { repeatable = true })
        mp.add_forced_key_binding("RIGHT", "jright", key_right)
        mp.add_forced_key_binding("DOWN", "jdown", key_down, { repeatable = true })
        mp.add_forced_key_binding("LEFT", "jleft", key_left)
        if #api_key <= 0 then connect() end
        if #items == 0 then
            update_overlay()
        else
            update_data()
        end
    end
    shown = not shown
end

local function disable_overlay()
    shown = true
    toggle_overlay()
end

local function split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

local function check_percent()
    local pos = mp.get_property_number("percent-pos")
    if pos == nil then return end
    if pos <= 94 or #items == 0 then return end
    local path = mp.get_property("path")
    if path == nil then return end
    local video_id = split(path, '/')[4]
    local UserData = nil -- pointer
    for i = 1, #items do
        if items[i].Id == video_id then
            UserData = items[i].UserData
            break
        end
    end
    if UserData == nil then return end
    if UserData.Played == false then
        local err = send_request_async("POST", options.url.."/Users/"..user_id.."/PlayedItems/"..video_id)
        if err == 0 then UserData.Played = true end
    end
end

local function unpause()
    mp.set_property_bool("pause", false)
    mp.set_property("force-media-title", "")
end

local function url_fix(str) -- add more later?
    return string.gsub(str, " ", "%%20")
end

local function search(query, err)
    if query ~= nil then
        local result = url_fix(query)
        user_query = result.."&recursive=true"
        shown = false
        items = {}
        toggle_overlay()
    end
end

local function search_input()
    input.get_user_input(search)
end

local function set_align()
    --align_main = "{\\a0}" -- Doesn't need to change
    align_other = "{\\a"..((4-align_x)+align_y).."}"
end

local function align_x_change(name, data)
    if data == "right" then
        align_x = 3
    elseif data == "center" then
        align_x = 2
    else
        align_x = 1
    end
    set_align()
end

local function align_y_change(name, data)
    if data == "bottom" then
        align_y = 0
    elseif data == "center" then
        align_y = 8
    else
        align_y = 4
    end
    set_align()
end

local function enable_overlay_on_idle(_, is_idle)
    if is_idle and not shown then
        toggle_overlay()
    end
end

mp.add_periodic_timer(1, check_percent)
mp.add_key_binding("Ctrl+j", "jf", toggle_overlay)
mp.add_key_binding("ESC", nil, disable_overlay)
if options.hide_images ~= "on" then
    mkdir(options.image_path)
    mp.observe_property("osd-width", "number", width_change)
end
mp.observe_property("osd-align-x", "string", align_x_change)
mp.observe_property("osd-align-y", "string", align_y_change)
mp.register_event("end-file", unpause)
if input_success then
    mp.add_key_binding("Ctrl+f", "jf_search", search_input)
end
if options.show_by_default == "on" then toggle_overlay() end
if options.show_on_idle == "on" then
    mp.observe_property("idle-active", "bool", enable_overlay_on_idle)
end
