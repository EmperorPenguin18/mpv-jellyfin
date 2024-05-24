local opt = require 'mp.options'
local utils = require 'mp.utils'

local options = {
	url = "",
	username = "",
	password = "",
	image_path = "",
	hide_spoilers = "on"
}
opt.read_options(options, mp.get_script_name())

local overlay = mp.create_osd_overlay("ass-events")
local meta_overlay = mp.create_osd_overlay("ass-events")
local connected = false
local shown = false
local user_id = ""
local api_key = ""

local parent_id = {"", "", ""}
local selection = {1, 1, 1}
local list_start = {1, 1, 1}
local layer = 1

local items = {}
local ow, oh, op = 0, 0, 0
local video_id = ""
local async = nil

local toggle_overlay -- function

local function send_request(method, url)
	if connected then
		local request = mp.command_native({
			name = "subprocess",
			capture_stdout = true,
			capture_stderr = true,
			playback_only = false,
			args = {"curl", "-X", method, url}
		})
		return utils.parse_json(request.stdout)
	end
	return nil
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
		if items[i].IndexNumber and items[i].IsFolder == false then
			index = items[i].IndexNumber..". "
		else
			-- nothing
		end
		if i == selection[layer] then
			overlay.data = overlay.data.."{\\fs16}{\\c&HFF&}"..index..items[i].Name.."\n"
		else
			overlay.data = overlay.data.."{\\fs16}"..index..items[i].Name.."\n"
		end
	end
	overlay:update()
end

local scale = 2 -- const

local function show_image(success, result, error, userdata)
	if success == true then
		mp.command_native({
			name = "overlay-add",
			id = 0,
			x = math.floor(ow/2.5),
			y = 10,
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
	mp.commandv("overlay-remove", "0")
	if item.ImageTags.Primary ~= nil then
		height = math.floor(width/item.PrimaryImageAspectRatio)
		filepath = options.image_path.."/"..item.Id.."_"..width.."_"..height..".bgra"
		if async ~= nil then mp.abort_async_command(async) end
		async = mp.command_native_async({
			name = "subprocess",
			playback_only = false,
			args = { "mpv", options.url.."/Items/"..item.Id.."/Images/Primary?api_key="..api_key.."&width="..width.."&height="..height, "--no-config", "--msg-level=all=no", "--vf=lavfi=[format=bgra]", "--of=rawvideo", "--o="..filepath }
		}, function(success, result, error) show_image(success, result, error, {width, height, filepath}) end)
	end
end

local function update_metadata(item)
	meta_overlay.data = ""
	local name = line_break(item.Name, "{\\a7}{\\fs24}", 30)
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
	meta_overlay.data = meta_overlay.data.."{\\a7}{\\fs16}"..year..time..rating..watched..favourite.."\n\n"
	local tagline = line_break(item.Taglines[1], "{\\a7}{\\fs20}", 35)
	meta_overlay.data = meta_overlay.data..tagline.."\n"
	local description = line_break(item.Overview, "{\\a7}{\\fs16}"..hidden, 45)
	meta_overlay.data = meta_overlay.data..description
	meta_overlay:update()
end

local function update_data()
	update_list()
	local item = items[selection[layer]]
	update_image(item)
	update_metadata(item)
end

local function update_overlay()
	overlay.data = "{\\fs16}Loading..."
	overlay:update()
	local url = options.url.."/Items?api_key="..api_key.."&userID="..user_id.."&parentId="..parent_id[layer].."&enableImageTypes=Primary&imageTypeLimit=1&fields=PrimaryImageAspectRatio,Taglines,Overview"
	if layer == 2 then
		url = url.."&sortBy=SortName"
	else
		-- nothing
	end
	items = send_request("GET", url).Items
	ow, oh, op = mp.get_osd_size()
	update_data()
end

local function width_change(name, data)
	if shown then update_overlay() end
end

local function play_video()
	toggle_overlay()
	mp.commandv("loadfile", options.url.."/Videos/"..video_id.."/stream?static=true&api_key="..api_key)
	mp.set_property("force-media-title", items[selection[layer]].Name)
end

local function key_up()
	if #items > 1 then
		selection[layer] = selection[layer] - 1
		if selection[layer] == 0 then selection[layer] = #items end
		update_data()
	end
end

local function key_right()
	if items[selection[layer]].IsFolder == false then
		video_id = items[selection[layer]].Id
		play_video()
	else
		layer = layer + 1 -- shouldn't get too big
		parent_id[layer] = items[selection[layer-1]].Id
		selection[layer] = 1
		update_overlay()
	end
end

local function key_down()
	if #items > 1 then
		selection[layer] = selection[layer] + 1
		if selection[layer] > #items then selection[layer] = 1 end
		update_data()
	end
end

local function key_left()
	if layer == 1 then return end
	layer = layer - 1
	update_overlay()
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
	connected = true
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
		if not connected then connect() end
		if #items == 0 then
			update_overlay()
		else
			update_data()
		end
	end
	shown = not shown
end

local function check_percent()
	local pos = mp.get_property_number("percent-pos")
	if pos then
		if pos > 95 and #video_id > 0 then
			send_request("POST", options.url.."/Users/"..user_id.."/PlayedItems/"..video_id.."?api_key="..api_key)
			items[selection[layer]].UserData.Played = true
			video_id = ""
		end
	end
end

local function unpause()
	mp.set_property_bool("pause", false)
end

os.execute("mkdir -p "..options.image_path)
mp.add_periodic_timer(1, check_percent)
mp.add_key_binding("Ctrl+j", "jf", toggle_overlay)
mp.observe_property("osd-width", "number", width_change)
mp.register_event("end-file", unpause)
