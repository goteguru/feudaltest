function update_player_texture(player)
        local filename = minetest.get_modpath("player_textures").."/textures/player_"..player:get_player_name()
        local f = io.open(filename..".png")
        if f then
                f:close()
                default.player_set_textures(player, {"player_"..player:get_player_name()..".png"})
	else
		default.player_set_textures(player, {"skin_default.png"})
        end
end

minetest.register_on_joinplayer(update_player_texture)
