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
local library_id = nil
local title_id = nil
local season_id = nil
local video_id = ""
local selection = 1
local items = {}
local ow, oh, op = 0, 0, 0

local toggle_overlay

local function send_request(url)
	if connected then
		local request = mp.command_native({
			name = "subprocess",
			capture_stdout = true,
			capture_stderr = true,
			playback_only = false,
			args = {"curl", url}
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

local function update_metadata()
	local metadata = send_request(options.url.."/Users/"..user_id.."/Items/"..items[selection].Id.."?api_key="..api_key)
	local image_data = nil
	for _, image in ipairs(send_request(options.url.."/Items/"..metadata.Id.."/Images?api_key="..api_key)) do
		if image.ImageType == "Primary" then
			image_data = image
		end
	end
	mp.commandv("overlay-remove", "0")
	if image_data then
		local filepath = options.image_path.."/"..metadata.Name..".bgra"
		local ratio = image_data.Height / image_data.Width
		if ratio > 0.5 then
			local width = math.floor(ow/3)
			local height = math.floor(width*ratio)
			local res = mp.command_native({ name = "subprocess", args = { "mpv", options.url.."/Items/"..metadata.Id.."/Images/Primary?api_key="..api_key, "--no-config", "--msg-level=all=no", "--vf=lavfi=[scale="..width..":"..height..",format=bgra]", "--of=rawvideo", "--o="..filepath }, playback_only = false })
			mp.commandv("overlay-add", "0", tostring(math.floor(ow/2.5)), tostring(10), filepath, "0", "bgra", tostring(width), tostring(height), tostring(width*4))
		end
	end

	meta_overlay.data = ""
	local name = line_break(metadata.Name, "{\\a7}{\\fs24}", 30)
	meta_overlay.data = meta_overlay.data..name.."\n"
	local year = ""
	if metadata.ProductionYear then year = metadata.ProductionYear end
	local time = ""
	if metadata.RunTimeTicks then time = "   "..math.floor(metadata.RunTimeTicks/600000000).."m" end
	local rating = ""
	if metadata.CommunityRating then rating = "   "..metadata.CommunityRating end
	local hidden = ""
	local watched = ""
	if metadata.UserData.Played == false then
		if options.hide_spoilers ~= "off" then hidden = "{\\bord0}{\\1a&HFF&}" end
	else
		watched = "   Watched"
	end
	local favourite = ""
	if metadata.UserData.IsFavorite == true then
		favourite = "   Favorite"
	end
	meta_overlay.data = meta_overlay.data.."{\\a7}{\\fs16}"..year..time..rating..watched..favourite.."\n\n"
	local tagline = line_break(metadata.Taglines[1], "{\\a7}{\\fs20}", 35)
	meta_overlay.data = meta_overlay.data..tagline.."\n"
	local description = line_break(metadata.Overview, "{\\a7}{\\fs16}"..hidden, 45)
	meta_overlay.data = meta_overlay.data..description
	meta_overlay:update()
end

local function update_data()
	overlay.data = ""
	for _, item in ipairs(items) do
		if _ > selection - (53 / op) then
			if _ < selection + (20 * op) then
				if _ == selection then
					overlay.data = overlay.data.."{\\fs16}{\\c&HFF&}"..item.Name.."\n"
				else
					overlay.data = overlay.data.."{\\fs16}"..item.Name.."\n"
				end
			end
		end
	end
	overlay:update()
end

local function resize()
	ow, oh, op = mp.get_osd_size()
end

local function refresh()
	resize()
	update_data()
	update_metadata()
end

local function property_change(name, data)
	refresh()
end

local function update_overlay()
	local result
	if not library_id then
		result = send_request(options.url.."/Items?api_key="..api_key.."&userID="..user_id)
	elseif not title_id then
		result = send_request(options.url.."/Items?api_key="..api_key.."&userID="..user_id.."&parentId="..library_id.."&sortBy=SortName")
	elseif not season_id then
		result = send_request(options.url.."/Items?api_key="..api_key.."&userID="..user_id.."&parentId="..title_id)
	else
		result = send_request(options.url.."/Items?api_key="..api_key.."&userID="..user_id.."&parentId="..season_id)
	end
	items = result.Items
	if ow > 0 then refresh() end
end

local function play_video()
	toggle_overlay()
	mp.commandv("loadfile", options.url.."/Videos/"..video_id.."/stream?static=true&api_key="..api_key)
	mp.set_property("force-media-title", items[selection].Name)
end

local function key_up()
	selection = selection - 1
	if selection == 0 then selection = table.getn(items) end
	update_data()
	update_metadata()
end

local function key_right()
	if items[selection].MediaType == "Video" then
		video_id = items[selection].Id
		play_video()
	else
		if not library_id then
			library_id = items[selection].Id
		elseif not title_id then
			title_id = items[selection].Id
		elseif not season_id then
			season_id = items[selection].Id
		end
		items = {}
		selection = 1
		update_overlay()
	end
end

local function key_down()
	selection = selection + 1
	if selection > table.getn(items) then selection = 1 end
	update_data()
	update_metadata()
end

local function key_left()
	if not library_id then
		return
	elseif not title_id then
		library_id = nil
	elseif not season_id then
		title_id = nil
	end
	items = {}
	selection = 1
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
		mp.unobserve_property(property_change)
		mp.commandv("overlay-remove", "0")
		overlay:remove()
		meta_overlay:remove()
	else
		mp.add_forced_key_binding("UP", "jup", key_up, { repeatable = true })
		mp.add_forced_key_binding("RIGHT", "jright", key_right)
		mp.add_forced_key_binding("DOWN", "jdown", key_down, { repeatable = true })
		mp.add_forced_key_binding("LEFT", "jleft", key_left)
		if not connected then
			mp.observe_property("osd-width", number, property_change)
			connect()
		end
		if table.getn(items) == 0 then
			update_overlay()
		else
			refresh()
		end
	end
	shown = not shown
end

local function mark_watched(data)
	if data.reason == "eof" then
		send_request(options.url.."/Users/"..user_id.."/PlayedItems/"..video_id.."?api_key="..api_key)
		video_id = ""
	end
end

mp.register_event("end-file", mark_watched)
mp.add_key_binding("Ctrl+j", "jf", toggle_overlay)
