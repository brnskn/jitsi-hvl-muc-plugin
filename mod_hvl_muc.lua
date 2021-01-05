-- Prosody IM
-- Copyright (C) 2017 Atlassian
--

function get_log()
	local log = { _version = "0.1.0" }
	log.usecolor = true
	log.outfile = nil
	log.level = "trace"

	local modes = {
		{ name = "trace", color = "\27[34m", },
		{ name = "debug", color = "\27[36m", },
		{ name = "info",  color = "\27[32m", },
		{ name = "warn",  color = "\27[33m", },
		{ name = "error", color = "\27[31m", },
		{ name = "fatal", color = "\27[35m", },
	}

	local levels = {}
	for i, v in ipairs(modes) do
		levels[v.name] = i
	end

	local round = function(x, increment)
		increment = increment or 1
		x = x / increment
		return (x > 0 and math.floor(x + .5) or math.ceil(x - .5)) * increment
	end

	local _tostring = tostring

	local tostring = function(...)
		local t = {}
		for i = 1, select('#', ...) do
			local x = select(i, ...)
			if type(x) == "number" then
			x = round(x, .01)
			end
			t[#t + 1] = _tostring(x)
		end
		return table.concat(t, " ")
	end

	for i, x in ipairs(modes) do
		local nameupper = x.name:upper()
		log[x.name] = function(...)
			
			-- Return early if we're below the log level
			if i < levels[log.level] then
				return
			end

			local msg = tostring(...)
			local info = debug.getinfo(2, "Sl")
			local lineinfo = info.short_src .. ":" .. info.currentline

			-- Output to console
			print(string.format("%s[%-6s%s]%s %s: %s",
								log.usecolor and x.color or "",
								nameupper,
								os.date("%H:%M:%S"),
								log.usecolor and "\27[0m" or "",
								lineinfo,
								msg))

			-- Output to log file
			if log.outfile then
				local fp = io.open(log.outfile, "a")
				local str = string.format("[%-6s%s] %s\n",
											nameupper, os.date("%m/%d/%Y %H:%M:%S"), msg)
				fp:write(str)
				fp:close()
			end

		end
	end
	return log
end


local log = get_log();
log.outfile = "hvl_muc.log";

local debug_log = get_log();
debug_log.outfile = "hvl_muc.debug.log";

local tostring = tostring;


local function starts_with(str, start)
	return str:sub(1, #start) == start
 end

local driver = require "luasql.sqlite3"
env = driver.sqlite3()
con = env:connect("logs.db")
res = con:execute[[
  CREATE TABLE IF NOT EXISTS rooms(
    jid  varchar(255) NOT NULL PRIMARY KEY,
    name varchar(255),
    password varchar(255),
    created_at varchar(255)
  )
]]

res = con:execute[[
  CREATE TABLE IF NOT EXISTS room_occupants(
    jid  varchar(255) NOT NULL,
    room_jid varchar(255) NOT NULL,
    email varchar(255),
	display_name varchar(255),
    created_at varchar(255),
	PRIMARY KEY (room_jid, display_name)
  )
]]

function room_created(event)
	debug_log.info("room_created ok");
	local room = event.room;

	if starts_with(room:get_name(), "org.jitsi.jicofo.health.health") then
		debug_log.info("room org.jitsi.jicofo.health.health ignored")
		return
	end

	log.info(string.format("room created: room=%s, room_jid=%s", room:get_name(), room.jid));

	res = con:execute(string.format([[
		INSERT INTO rooms
		VALUES ('%s', '%s', '%s', '%s')]], 
		room.jid, 
		room:get_name(), 
		room:get_password() or "",
		tostring(room.created_timestamp or os.time(os.date("!*t")) * 1000))
	)

	res = con:execute(string.format([[DELETE FROM room_occupants WHERE room_jid='%s']], 
		room.jid))
	
    debug_log.info(string.format([[room added INSERT INTO rooms VALUES ('%s', '%s', '%s', '%s')]], 
		room.jid, 
		room:get_name(), 
		room:get_password() or "",
		tostring(room.created_timestamp or os.time(os.date("!*t")) * 1000)));
end

function room_destroyed(event)
	debug_log.info("room_destroyed ok");
	local room = event.room;

	if starts_with(room:get_name(), "org.jitsi.jicofo.health.health") then
		debug_log.info("room org.jitsi.jicofo.health.health ignored")
		return
	end

	log.info(string.format("room destroyed: room=%s, room_jid=%s", room:get_name(), room.jid));
end

function occupant_joined(event)
    debug_log.info("occupant_joined ok");
	local room = event.room;

	if starts_with(room:get_name(), "org.jitsi.jicofo.health.health") then
		debug_log.info("room org.jitsi.jicofo.health.health ignored")
		return
	end

	local occupant = event.occupant;
	if string.sub(occupant.nick,-string.len("/focus"))~="/focus" then
		for _, pr in occupant:each_session() do
			local nick = pr:get_child_text("nick", "http://jabber.org/protocol/nick") or "";
			if nick~="" then
				local email = pr:get_child_text("email") or "";

				cur = con:execute(string.format("SELECT COUNT(*) as count FROM room_occupants WHERE room_jid='%s' AND jid='%s'", room.jid, tostring(occupant.nick)));
				
				if tonumber(cur:fetch({}, "a").count) > 0 then
					cur = con:execute(string.format("SELECT * FROM room_occupants WHERE room_jid='%s' AND jid='%s'", room.jid, tostring(occupant.nick)));
					old_room = cur:fetch({}, "a");
					
					debug_log.info(string.format("occupant changed old name %s new name %s", old_room.display_name, tostring(nick)))
					if old_room.display_name~=tostring(nick) then
						debug_log.info("occupant changed if check ok")
						log.info(string.format("occupant changed username: room=%s, room_jid=%s, user_jid=%s, nick=%s, old_nick=%s", room:get_name(), room.jid, tostring(occupant.nick), tostring(nick), old_room.display_name));
					end

					res = assert(con:execute(string.format([[
						UPDATE room_occupants
						SET email='%s', display_name='%s' WHERE room_jid='%s' AND jid='%s']], 
						tostring(email), 
						tostring(nick),
						room.jid, 
						tostring(occupant.nick)
					)))

					debug_log.info(string.format([[occupant changed UPDATE room_occupants SET email='%s', display_name='%s' WHERE room_jid='%s' AND jid='%s')]], 
						tostring(email), 
						tostring(nick),
						room.jid, 
						tostring(occupant.nick)));
				else
					res = con:execute(string.format([[
						INSERT INTO room_occupants
						VALUES ('%s', '%s', '%s', '%s', '%s')]], 
						tostring(occupant.nick), 
						room.jid, 
						tostring(email), 
						tostring(nick),
						tostring(os.time(os.date("!*t")) * 1000) or ""
					))

					debug_log.info(string.format([[occupant added INSERT INTO room_occupants VALUES ('%s', '%s', '%s', '%s')]], 
							tostring(occupant.nick), 
							room.jid, 
							tostring(email), 
							tostring(nick)));
				end
			end
		end
	end
end


function occupant_joined_log(event)
    debug_log.info("occupant_joined_log ok");
	local room = event.room;

	if starts_with(room:get_name(), "org.jitsi.jicofo.health.health") then
		debug_log.info("room org.jitsi.jicofo.health.health ignored")
		return
	end

	local occupant = event.occupant;
	if occupant then
		if string.sub(occupant.nick,-string.len("/focus"))~="/focus" then
			for _, pr in occupant:each_session() do
				local nick = pr:get_child_text("nick", "http://jabber.org/protocol/nick") or "no_name";
				log.info(string.format("occupant joined: room=%s, room_jid=%s, user_jid=%s, nick=%s", room:get_name(), room.jid, tostring(occupant.nick), tostring(nick)));
			end
		end
	end
end

function occupant_left_log(event)
    debug_log.info("occupant_left_log ok");
	local room = event.room;

	if starts_with(room:get_name(), "org.jitsi.jicofo.health.health") then
		debug_log.info("room org.jitsi.jicofo.health.health ignored")
		return
	end

	local occupant = event.occupant;
	

	if string.sub(occupant.nick,-string.len("/focus"))~="/focus" then

		res = con:execute(string.format([[DELETE FROM room_occupants WHERE room_jid = '%s' AND jid = '%s']], 
			room.jid,	
			tostring(occupant.nick)))

		debug_log.info(string.format([[occupant left DELETE FROM room_occupants WHERE room_jid = '%s' AND jid = '%s')]], 
			room.jid, 
			tostring(occupant.nick)));


		for _, pr in occupant:each_session() do
			local nick = pr:get_child_text("nick", "http://jabber.org/protocol/nick") or "no_name";
			log.info(string.format("occupant left: room=%s, room_jid=%s, user_jid=%s, nick=%s", room:get_name(), room.jid, tostring(occupant.nick), tostring(nick)));
		end

		

	end

end

function module.load()
	module:hook("muc-room-created", room_created, -1);
	module:hook("muc-room-created", occupant_joined_log, -1);

	module:hook("muc-room-destroyed", room_destroyed, -1);

	module:hook("muc-occupant-joined", occupant_joined, -1);
	module:hook("muc-occupant-joined", occupant_joined_log, -1);

	module:hook("muc-occupant-pre-leave", occupant_left_log, -1);
	
	module:hook("muc-broadcast-presence", occupant_joined, -1);
	debug_log.info("hooks ok ",module.host);
end

