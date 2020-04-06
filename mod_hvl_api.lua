-- Prosody IM
-- Copyright (C) 2017 Atlassian
--

local jid = require "util.jid";
local it = require "util.iterators";
local json = require "util.json";
local iterators = require "util.iterators";
local array = require"util.array";

local have_async = pcall(require, "util.async");
if not have_async then
    module:log("error", "requires a version of Prosody with util.async");
    return;
end

local async_handler_wrapper = module:require "util".async_handler_wrapper;

local tostring = tostring;

function urldecode(s)
	s = s:gsub('+', ' ')
		 :gsub('%%(%x%x)', function(h)
							 return string.char(tonumber(h, 16))
						   end)
	return s
end
   
function parse(s)
	local ans = {}
	for k,v in s:gmatch('([^&=?]-)=([^&=?]+)' ) do
	  ans[ k ] = urldecode(v)
	end
	return ans
end


-- option to enable/disable room API token verifications
local get_room_from_jid = module:require "util".get_room_from_jid;

local driver = require "luasql.sqlite3"
env = driver.sqlite3()

-- no token configuration but required

-- required parameter for custom muc component prefix,
-- defaults to "conference"
local muc_domain_prefix
	= module:get_option_string("muc_mapper_domain_prefix", "conference");

local muc_component_host = nil;

--- Handles request for retrieving the room size
-- @param event the http event, holds the request query
-- @return GET response, containing a json with participants count,
--         tha value is without counting the focus.
function get_room_size(event)
    if (not event.request.url.query) then
        return { status_code = 400; };
    end

	local params = parse(event.request.url.query);
	local room_name = params["room"];

    local room_address
        = jid.join(room_name, muc_component_host);

	local room = get_room_from_jid(room_address);
	local participant_count = 0;

	log("debug", "Querying room %s", tostring(room_address));

	if room then
		local occupants = room._occupants;
		if occupants then
			participant_count = iterators.count(room:each_occupant());
		end
		log("debug",
            "there are %s occupants in room", tostring(participant_count));
	else
		log("debug", "no such room exists");
		return { status_code = 404; };
	end

	if participant_count > 1 then
		participant_count = participant_count - 1;
	end

	return { status_code = 200; body = [[{"participants":]]..participant_count..[[}]] };
end

--- Handles request for retrieving the room participants details
-- @param event the http event, holds the request query
-- @return GET response, containing a json with room and participants details
function get_room (event)
    if (not event.request.url.query) then
        return { status_code = 400; };
    end

	local params = parse(event.request.url.query);
	local room_name = params["room"];
    local room_address
        = jid.join(room_name, muc_component_host);

	local room = get_room_from_jid(room_address);
	local participant_count = 0;
	local occupants_json = array();
	local room_json = {};

	log("debug", "Querying room %s", tostring(room_address));

	if room then
		local password = room:get_password() or "";

        if room.created_timestamp == nil then
            room.created_timestamp = os.time(os.date("!*t")) * 1000;
		end
		
		room_json = { 
			jid = room.jid, 
			name = room:get_name(),
			password = password,
			conference_duration = room.created_timestamp
		}

		local occupants = room._occupants;
		if occupants then
			participant_count = iterators.count(room:each_occupant());
			for _, occupant in room:each_occupant() do
			    -- filter focus as we keep it as hidden participant
			    if string.sub(occupant.nick,-string.len("/focus"))~="/focus" then
				    for _, pr in occupant:each_session() do
						local nick = pr:get_child_text("nick", "http://jabber.org/protocol/nick") or "";
						local email = pr:get_child_text("email") or "";
						occupants_json:push({
							jid = tostring(occupant.nick),
							email = tostring(email),
							display_name = tostring(nick)});
				    end
			    end
			end
		end
		log("debug",
            "there are %s occupants in room", tostring(participant_count));
	else
		log("debug", "no such room exists");
		return { status_code = 404; };
	end

	if participant_count > 1 then
		participant_count = participant_count - 1;
	end

	return { status_code = 200; body = json.encode({
		room = room_json,
		occupants = occupants_json
	}); };
end

--- Handles request for creating new room
-- @param event the http event, holds the request query
-- @return GET response, containing a json with added room details
function create_room (event)
    if (not event.request.url.query) then
        return { status_code = 400; };
	end

	local params = parse(event.request.url.query);
	local room_name = params["room"];
	local room_address
        = jid.join(room_name, muc_component_host);
		
	local component = hosts[muc_component_host];
	if component then
		local muc = component.modules.muc;
		local room = muc.create_room(room_address);
		if room then
			return { status_code = 200; };
		else
			return { status_code = 500; };
		end
	else
        return { status_code = 404; };
	end
end

--- Handles request for deleting room
-- @param event the http event, holds the request query
-- @return GET response
function destroy_room(event)
    if (not event.request.url.query) then
        return { status_code = 400; };
	end
	local params = parse(event.request.url.query);
	local room_name = params["room"];
	local room_address
		= jid.join(room_name, muc_component_host);
	local room = get_room_from_jid(room_address);
	if not room then
        return { status_code = 404; };
	end
	room:destroy();
	return { status_code = 200; };
end

--- Handles request for deleting room
-- @param event the http event, holds the request query
-- @return GET response
function change_room(event)
    if (not event.request.url.query) then
        return { status_code = 400; };
	end
	local params = parse(event.request.url.query);
	local room_name = params["room"];
	local password = params["password"];
	local room_address
		= jid.join(room_name, muc_component_host);
	local room = get_room_from_jid(room_address);
	if not room then
        return { status_code = 404; };
	end
	if password then
		room:set_password(room, password);
	end
	return { status_code = 200; };
end

function rooms()
	local room_list = array();
	local component = hosts[muc_component_host];
	if component then
		local muc = component.modules.muc
		local rooms = nil;
		if muc and rawget(muc,"rooms") then
			return muc.rooms;
		elseif muc and rawget(muc,"live_rooms") then
			rooms = muc.live_rooms();
		elseif muc and rawget(muc,"each_room") then
			rooms = muc.each_room(true);
		end
		if rooms then
			for room in rooms do
				local jid_name, room_name = room.jid, room:get_name();
				room_list:push({ 
					jid = jid_name, 
					name = room_name
				});
			end
		end
	end
	return { status_code = 200; body = json.encode(room_list); };
end

function rows (connection, sql_statement)
	local cursor = assert (connection:execute (sql_statement))
	return function ()
	  return cursor:fetch()
	end
end

function get_room_stats(event)
	local con = env:connect("logs.db");
	local params = parse(event.request.url.query or "");
	local page = params["page"] or 1;
	local page_size = 25;
	local offset = (page - 1) * page_size;
	cur = con:execute"SELECT COUNT(*) as count FROM rooms";
	local total_page = math.ceil(tonumber(cur:fetch({}, "a").count) / page_size);
	cur:close();
	local rooms = array();
	for jid, name, password, created_at in rows (con, string.format("SELECT * FROM rooms LIMIT %s,%s", offset, page_size)) do
		local occupants = array();
		for user_jid, room_jid, email, display_name, user_created_at in rows (con, string.format("SELECT * FROM room_occupants WHERE room_jid='%s'", jid)) do
			occupants:push({ 
				jid = user_jid, 
				room_jid = room_jid, 
				email = email,
				display_name = display_name,
				created_at = user_created_at,
			});
		end
		rooms:push({ 
			jid = jid, 
			name = name,
			password = password,
			created_at = created_at,
			occupants = occupants
		});
	end
	con:close();
	return { status_code = 200; body = json.encode({
		current_page = page,
		total_page = total_page,
		page_size = page_size,
		data = rooms
	}); };
end

function module.load()
    module:depends("http");
	module:provides("http", {
		default_path = "/";
		route = {
			["GET room-size"] = function (event) return async_handler_wrapper(event,get_room_size) end;
			["GET sessions"] = function () return tostring(it.count(it.keys(prosody.full_sessions))); end;
			["GET rooms"] = function (event) return async_handler_wrapper(event,rooms) end;
			["GET room"] = function (event) return async_handler_wrapper(event,get_room) end;
			["PUT room"] = function (event) return async_handler_wrapper(event,create_room) end;
			["DELETE room"] = function (event) return async_handler_wrapper(event,destroy_room) end;
			["PATCH room"] = function (event) return async_handler_wrapper(event,change_room) end;
			["GET room_stats"] = function (event) return async_handler_wrapper(event,get_room_stats) end;
		};
	});
end


function process_host(host)
	for _, host in pairs(hosts) do
		local node, hostname = jid.split(tostring(host.host));
		if hostname:match"([^.]*).(.*)" == muc_domain_prefix then
			muc_component_host = host.host;
		end
	end
end

if prosody.hosts[muc_component_host] == nil then
	prosody.events.add_handler("host-activated", process_host);
else
    process_host(muc_component_host);
end