local r = ctf.setting("flag.nobuild_radius")
local c_air = minetest.get_content_id("air")

local function elementsInTable(t)
   local n = 0
   for _ in pairs(t) do n = n + 1 end
   return n
end

local function recalc_team_maxpower(team)
   team.power.max_power = ctf.get_team_maxpower(team)
end

local function can_place_flag(pos)
	local lpos = pos
	local pos1 = {x=lpos.x-r+1,y=lpos.y,z=lpos.z-r+1}
	local pos2 = {x=lpos.x+r-1,y=lpos.y+r-1,z=lpos.z+r-1}

	local vm = minetest.get_voxel_manip()

	local emin, emax = vm:read_from_map(pos1, pos2)
	local a = VoxelArea:new{
		MinEdge = emin,
		MaxEdge = emax
	}

	local nx = lpos.x
	local ny = lpos.y
	local nz = lpos.z

	local n1x = pos1.x
	local n1y = pos1.y
	local n1z = pos1.z

	local n2x = pos2.x
	local n2y = pos2.y
	local n2z = pos2.z

	local data = vm:get_data()

	local m_vi = a:index(nx, ny, nz)
	local myname = minetest.get_name_from_content_id(data[m_vi])

	for z = n1z, n2z do
		for y = n1y, n2y do
			for x = n1x, n2x do
				if x ~= nx or y ~= ny or z ~= nz then
					local vi = a:index(x, y, z)
					local id = data[vi]
					if id ~= c_air then
						return false
					end
				end
			end
		end
    end
	return true
end

local function do_capture(attname, flag, returned)
	local team = flag.team
	local attacker = ctf.player(attname)

	local flag_name = ""
	if flag.name then
		flag_name = flag.name .. " "
	end
	flag_name = team .. "'s " .. flag_name .. "flag"


	if ctf.setting("flag.capture_take") and not returned then
		for i = 1, #ctf_flag.registered_on_prepick_up do
			if not ctf_flag.registered_on_prepick_up[i](attname, flag) then
				return
			end
		end

		minetest.chat_send_all(flag_name.." has been picked up by "..
				attname.." (team "..attacker.team..")")

		ctf.action("flag", attname .. " picked up " .. flag_name)

		-- Post to flag owner's board
		ctf.post(team, {
				msg = flag_name .. " has been taken by " .. attname .. " of ".. attacker.team,
				icon="flag_red" })

		-- Post to attacker's board
		ctf.post(attacker.team, {
				msg = attname .. " snatched '" .. flag_name .. "' from " .. team,
				icon="flag_green"})

		-- Add to claimed list
		flag.claimed = {
			team = attacker.team,
			player = attname
		}

		ctf.hud.updateAll()

		ctf_flag.update(flag)

		for i = 1, #ctf_flag.registered_on_pick_up do
			ctf_flag.registered_on_pick_up[i](attname, flag)
		end
	else
		for i = 1, #ctf_flag.registered_on_precapture do
			if not ctf_flag.registered_on_precapture[i](attname, flag) then
				return
			end
		end

      -- Check if this team has any power / online memebers
      local tData = ctf.team(team)
      if ctf.team_has_online_players(team) == false then
         if tData.power.power > 0 then
            minetest.chat_send_player(attname, "You cannot capture this flag right now.")
            return
         end
      end

		minetest.chat_send_all(flag_name.." has been captured "..
				" by "..attname.." (team "..attacker.team..")")
      if irc then
         irc:say(flag_name.." has been captured by "..attname.." (team "..attacker.team..")")
      end

		ctf.action("flag", attname .. " captured " .. flag_name)

		-- Post to flag owner's board
		ctf.post(team, {
				msg = flag_name .. " has been captured by " .. attacker.team,
				icon="flag_red"})

		-- Post to attacker's board
		ctf.post(attacker.team, {
				msg = attname .. " captured '" .. flag_name .. "' from " .. team,
				icon="flag_green"})

		-- Take flag
		if ctf.setting("flag.allow_multiple") then
			ctf_flag.delete(team, vector.new(flag))
			ctf_flag.add(attacker.team, vector.new(flag))
		else
			minetest.set_node(pos,{name="air"})
			ctf_flag.delete(team,pos)
		end

      -- Recalculate team maxpowers
      local aTeam = ctf.team(attacker.team)
      recalc_team_maxpower(tData)
      recalc_team_maxpower(aTeam)

		for i = 1, #ctf_flag.registered_on_capture do
			ctf_flag.registered_on_capture[i](attname, flag)
		end
	end
	ctf.needs_save = true
end

local function player_drop_flag(player)
	return ctf_flag.player_drop_flag(player:get_player_name())
end
minetest.register_on_dieplayer(player_drop_flag)
minetest.register_on_leaveplayer(player_drop_flag)


ctf_flag = {
	on_punch_top = function(pos, node, puncher)
		pos.y = pos.y - 1
		ctf_flag.on_punch(pos, node, puncher)
	end,
	on_rightclick_top = function(pos, node, clicker)
		pos.y = pos.y - 1
		ctf_flag.on_rightclick(pos, node, clicker)
	end,
	on_rightclick = function(pos, node, clicker)
		local name = clicker:get_player_name()
		local flag = ctf_flag.get(pos)
		if not flag then
			return
		end

		if flag.claimed then
			if ctf.setting("flag.capture_take") then
				minetest.chat_send_player(name, "This flag has been taken by " .. flag.claimed.player)
				minetest.chat_send_player(name, "who is a member of team " .. flag.claimed.team)
				return
			else
				minetest.chat_send_player(name, "Oops! This flag should not be captured. Reverting...")
				flag.claimed = nil
			end
		end
		ctf.gui.flag_board(name, pos)
	end,
	on_punch = function(pos, node, puncher)
		local name = puncher:get_player_name()
		if not puncher or not name then
			return
		end

		local flag = ctf_flag.get(pos)
		if not flag then
			return
		end

		if flag.claimed then
			if ctf.setting("flag.capture_take") then
				minetest.chat_send_player(name, "This flag has been taken by " .. flag.claimed.player)
				minetest.chat_send_player(name, "who is a member of team " .. flag.claimed.team)
				return
			else
				minetest.chat_send_player(name, "Oops! This flag should not be captured. Reverting.")
				flag.claimed = nil
			end
		end

		local team = flag.team
		if not team then
			return
		end

		if ctf.team(team) and ctf.player(name).team then
			if ctf.player(name).team == team then
				-- Clicking on their team's flag
				if ctf.setting("flag.capture_take") then
					ctf_flag._flagret(name)
				end
			else
				-- Clicked on another team's flag
				local diplo = ctf.diplo.get(team, ctf.player(name).team) or
						ctf.setting("default_diplo_state")

				if diplo ~= "war" then
					minetest.chat_send_player(name, "You are at peace with this team!")
					return
				end

				local g_pos = players_glitching[name]
				if g_pos then
					minetest.get_player_by_name(name):set_pos(g_pos)
					minetest.chat_send_player(name, "You can't capture the flag by glitching!")
					return
				end

				do_capture(name, flag)
			end
		else
			minetest.chat_send_player(name, "You are not part of a team!")
		end
	end,
	_flagret = function(name)
		local claimed = ctf_flag.collect_claimed()
		for i = 1, #claimed do
			local flag = claimed[i]
			if flag.claimed.player == name then
				do_capture(name, flag, true)
			end
		end
	end,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", "Unowned flag")
		minetest.get_node_timer(pos):start(5)
	end,
	on_place = function(itemstack, placer, pointed_thing)
		if not placer then
			return itemstack
		end

		local name = placer:get_player_name()
		local node = minetest.get_node(pointed_thing.under)
		local nodedef = minetest.registered_nodes[node.name]

		if nodedef and nodedef.on_rightclick and
				not placer:get_player_control().sneak then
			return nodedef.on_rightclick(pointed_thing.under,
					node, placer, itemstack, pointed_thing)
		end

		local pos
		if nodedef and nodedef.buildable_to then
			pos = pointed_thing.under
		else
			pos = pointed_thing.above
			node = minetest.get_node(pos)
			nodedef = minetest.registered_nodes[node.name]
			if not nodedef or not nodedef.buildable_to then
				return itemstack
			end
		end

		local meta = minetest.get_meta(pos)
		if not meta then
			return itemstack
		end

		if pos.y < -50 then
			minetest.chat_send_player(name, "Max flag depth is 50 blocks.")
			return itemstack
		end

		if not can_place_flag(pos) then
			minetest.chat_send_player(name, "Too close to the flag to build!"
						.. " Leave at least " .. r .. " blocks around the flag.")
			return itemstack
		end

		local tplayer = ctf.player_or_nil(name)
		if tplayer and ctf.team(tplayer.team) then
			if ctf.player(name).auth == false then
				minetest.chat_send_player(name, "You're not allowed to place flags!")
				return itemstack
			end

         local tname = tplayer.team
			local team = ctf.team(tplayer.team)

			if elementsInTable(team.players) <= elementsInTable(team.flags) then
				minetest.chat_send_player(name, "You need more members to be able to place more flags.")
				return itemstack
			end

			meta:set_string("infotext", tname .. "'s flag")

			-- add flag
			ctf_flag.add(tname, pos)

			-- TODO: fix this hackiness
			if team.spawn and not ctf.setting("flag.allow_multiple") and
					minetest.get_node(team.spawn).name == "ctf_flag:flag" then
				-- send message
				minetest.chat_send_all(tname .. "'s flag has been moved")
				minetest.set_node(team.spawn, {name="air"})
				minetest.set_node({
					x = team.spawn.x,
					y = team.spawn.y + 1,
					z = team.spawn.z
				}, {name = "air"})
				team.spawn = pos
			end

			ctf.needs_save = true

			local pos2 = {
				x = pos.x,
				y = pos.y + 1,
				z = pos.z
			}

			if not team.data.color then
				team.data.color = "red"
				ctf.needs_save = true
			end

         -- Recalc team max power
         recalc_team_maxpower(team)

			minetest.set_node(pos, {name = "ctf_flag:flag"})
			minetest.set_node(pos2, {name = "ctf_flag:flag_top_" .. team.data.color})

			local meta2 = minetest.get_meta(pos2)
			meta2:set_string("infotext", tname.."'s flag")

			itemstack:take_item()
			return itemstack
		else
			minetest.chat_send_player(name, "You are not part of a team!")
			return itemstack
		end
	end
}
