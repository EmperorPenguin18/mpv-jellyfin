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
local library_selection = 1
local title_id = nil
local title_selection = 1
local season_id = nil
local season_selection = 1
local video_id = ""
local selection = 1
local items = {}
local ow, oh, op = 0, 0, 0

local toggle_overlay

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
	local id = items[selection].Id
	local width = math.floor(ow/3)
	local height = 0
	local filepath = ""
	for _, image in ipairs(send_request("GET", options.url.."/Items/"..id.."/Images?api_key="..api_key)) do
		if image.ImageType == "Primary" then
			height = math.floor( width*(image.Height / image.Width) )
			filepath = options.image_path.."/"..id.."_"..width.."_"..height..".bgra"
			mp.command_native({
				name = "subprocess",
				playback_only = false,
				args = { "mpv", options.url.."/Items/"..id.."/Images/Primary?api_key="..api_key, "--no-config", "--msg-level=all=no", "--vf=lavfi=[scale="..width..":"..height..",format=bgra]", "--of=rawvideo", "--o="..filepath }
			})
			break
		end
	end
	mp.commandv("overlay-remove", "0")
	mp.commandv("overlay-add", "0", tostring(math.floor(ow/2.5)), tostring(10), filepath, "0", "bgra", tostring(width), tostring(height), tostring(width*4))
	meta_overlay.data = ""
	local metadata = send_request("GET", options.url.."/Users/"..user_id.."/Items/"..id.."?api_key="..api_key)
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

local function update_overlay()
	overlay.data = "{\\fs16}Loading..."
	overlay:update()
	local result
	if not library_id then
		result = send_request("GET", options.url.."/Items?api_key="..api_key.."&userID="..user_id)
	elseif not title_id then
		result = send_request("GET", options.url.."/Items?api_key="..api_key.."&userID="..user_id.."&parentId="..library_id.."&sortBy=SortName")
	elseif not season_id then
		result = send_request("GET", options.url.."/Items?api_key="..api_key.."&userID="..user_id.."&parentId="..title_id)
	else
		result = send_request("GET", options.url.."/Items?api_key="..api_key.."&userID="..user_id.."&parentId="..season_id)
	end
	items = result.Items
	heights = {}
	ow, oh, op = mp.get_osd_size()
	update_data()
end

local function width_change(name, data)
	if shown then update_overlay() end
end

local function play_video()
	toggle_overlay()
	mp.commandv("loadfile", options.url.."/Videos/"..video_id.."/stream?static=true&api_key="..api_key)
	mp.set_property("force-media-title", items[selection].Name)
end

local function key_up()
	selection = selection - 1
	if selection == 0 then selection = #items end
	update_data()
end

local function key_right()
	if items[selection].IsFolder == false then
		video_id = items[selection].Id
		play_video()
	else
		if not library_id then
			library_id = items[selection].Id
			library_selection = selection
		elseif not title_id then
			title_id = items[selection].Id
			title_selection = selection
		elseif not season_id then
			season_id = items[selection].Id
			season_selection = selection
		end
		selection = 1
		update_overlay()
	end
end

local function key_down()
	selection = selection + 1
	if selection > #items then selection = 1 end
	update_data()
end

local function key_left()
	if not library_id then
		return
	elseif not title_id then
		library_id = nil
		selection = library_selection
	elseif not season_id then
		title_id = nil
		selection = title_selection
	else
		season_id = nil
		selection = season_selection
	end
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
		if pos > 95 then
			send_request("POST", options.url.."/Users/"..user_id.."/PlayedItems/"..video_id.."?api_key="..api_key)
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
mp.register_event("file-loaded", unpause)
