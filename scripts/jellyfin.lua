local opt = require 'mp.options'
local utils = require 'mp.utils'

local options = {
	url = "",
	username = "",
	password = ""
}
opt.read_options(options, mp.get_script_name())

local overlay = mp.create_osd_overlay("ass-events")
local connected = false
local shown = false
local user_id = nil
local api_key = nil
local library_id = nil
local title_id = nil
local season_id = nil
local video_id = nil
local selection = 1
local items = {}

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

local function update_data()
	overlay.data = ""
	local ow, oh, op = mp.get_osd_size()
	for _, item in ipairs(items) do
		if _ >= selection - (19.5 * op / 1.12) + 1 then
			if _ - selection < (19.5 * op / 1.12) then
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
	update_data()
end

local function play_video()
	toggle_overlay()
	mp.commandv("loadfile", options.url.."/Videos/"..video_id.."/stream?static=true&api_key="..api_key)
end

local function key_up()
	selection = selection - 1
	if selection == 0 then selection = table.getn(items) end
	update_data()
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
end

local function key_left()
	if not library_id then
		--nothing
	elseif not title_id then
		library_id = nil
	elseif not season_id then
		title_id = nil
	end
	items = {}
	selection = 1
	update_overlay()
end

toggle_overlay = function()
	if shown then
		overlay:remove()
		mp.remove_key_binding("jup")
		mp.remove_key_binding("jright")
		mp.remove_key_binding("jdown")
		mp.remove_key_binding("jleft")
	else
		if not connected then connect() end
		if table.getn(items) == 0 then update_overlay() end
		mp.add_forced_key_binding("UP", "jup", key_up)
		mp.add_forced_key_binding("RIGHT", "jright", key_right)
		mp.add_forced_key_binding("DOWN", "jdown", key_down)
		mp.add_forced_key_binding("LEFT", "jleft", key_left)
	end
	shown = not shown
end

local function mark_watched(data)
	if data.reason == "eof" then
		send_request(options.url.."/Users/"..user_id.."/PlayedItems/"..video_id.."?api_key="..api_key)
		video_id = nil
	end
end

mp.register_event("end-file", mark_watched)
mp.add_key_binding("Ctrl+j", "jf", toggle_overlay)
