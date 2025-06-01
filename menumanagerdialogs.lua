local jss = JoiningScreenSelector.settings

function MenuManager:jss_on_joining_screen_kick(message_id, player_id)
	if not managers.hud:jss_peer_id() then
		return
	end
	
	if player_id > 4 then
		player_id = nil
	end
		
	local message_id = tonumber(message_id)
	local peer_id = player_id or tonumber(string.match(managers.system_menu._active_dialog:id(), "%d+"))
	if peer_id then
		local peer = managers.network._session:peer(peer_id)
			
		if peer then		
			managers.network:session():send_to_peers("kick_peer", peer_id, message_id)
			managers.network:session():on_peer_kicked(peer, peer_id, message_id)
			if message_id == 6 then
				local identifier = SystemInfo:matchmaking() ~= Idstring("MM_STEAM") and peer:account_id() or peer:user_id()
				managers.ban_list:ban(identifier, peer:name())
			end
		end
	end
end

function MenuManager:jss_on_joining_screen_confirm(id, nick, mode, text)
    local dialog_data = {    
		title = managers.localization:text("dialog_warning_title"),
		text = text .. " : " .. nick .. " | Player ID : " .. tostring(id),
		id = "jss_on_joining_screen_confirm"
	}
	
	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = function() self:jss_on_joining_screen_kick(mode, id) end
	}
	local no_button = {
		text = managers.localization:text("dialog_no"),
		callback_func = function() self:show_person_joining(id, nick) end
	}
	dialog_data.button_list = {
		yes_button,
		no_button
	}
	
    managers.system_menu:show_buttons(dialog_data)
end

function MenuManager:jss_end_game_instant(player_id)
	local is_joining = managers.hud:jss_peer_id() or player_id
	
	if is_joining ~= "-999" then
	    managers.platform:set_playing(false)
	    managers.job:clear_saved_ghost_bonus()
	    managers.statistics:stop_session({
		    quit = true
	    })
	    managers.savefile:save_progress()
	    managers.job:deactivate_current_job()
	    managers.gage_assignment:deactivate_assignments()
	    managers.custom_safehouse:flush_completed_trophies()
	    managers.crime_spree:on_left_lobby()

	    if Network:multiplayer() then
		    Network:set_multiplayer(false)
		    managers.network:session():send_to_peers("set_peer_left")
		    managers.network:queue_stop_network()
	    end

	    managers.network.matchmake:destroy_game()
	    managers.network.voice_chat:destroy_voice()
	    managers.groupai:state():set_AI_enabled(false)
	    managers.menu:post_event("menu_exit")
	    managers.menu:close_menu("menu_pause")
	    setup:load_start_menu()
	end
end

function MenuManager:jss_end_game_confirm(id, nick)
    local dialog_data = {    
		title = managers.localization:text("dialog_warning_title"),
		text = managers.localization:text("dialog_are_you_sure_you_want_to_leave_game"),
		id = "jss_end_game_confirm"
	}
	
	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = function() self:jss_end_game_instant(id) end
	}
	local no_button = {
		text = managers.localization:text("dialog_no"),
		callback_func = function() self:show_person_joining(id, nick) end
	}
	dialog_data.button_list = {
		yes_button,
		no_button
	}
	
    managers.system_menu:show_buttons(dialog_data)
end

Hooks:OverrideFunction(MenuManager, "show_person_joining", function(self, id, nick)
	self._jss_modlist = self._jss_modlist or {}
	managers.hud:updater_jss_peer_id(id)
	
	local peer = managers.network:session():peer(id)
	local level = managers.experience:gui_string(peer:level() or "???", peer:rank() or "???") .. " "
	local platform = "[" .. peer:account_type_str() .. "] "
	
	local player_data = {
		platform .. level,
		level,
		platform,
		""
	}
	
	local dialog_data = {
		title = managers.localization:text("dialog_dropin_title", {
			USER = player_data[jss.level_and_platform] .. string.upper(nick) 
		}),
		
		text = managers.localization:text("dialog_wait") .. " 0%" .. "\n ",
		id = "user_dropin" .. id
	}
	
	if Network:is_server() and jss.operate_type == 1 then
		local disconnect_peer = {
			text = "Disconnect",
			callback_func = function()
				self:jss_on_joining_screen_confirm(id, nick, 2, "Disconnect")
			end
		}

		local kick_peer = {
			text = "Kick Player",
			callback_func = function()
				self:jss_on_joining_screen_confirm(id, nick, 0, "Kick Player")
			end
		}
			
		local ban_peer = {
			text = "Ban Player",
			callback_func = function()
				self:jss_on_joining_screen_confirm(id, nick, 6, "Ban Player")
			end
		}

		dialog_data.button_list = {
				disconnect_peer,
				kick_peer,
				ban_peer
		}
	elseif not Network:is_server() and jss.operate_type == 1 then
	    local end_game = {
			text = managers.localization:text("menu_end_game"),
			callback_func = function()
				self:jss_end_game_confirm(id, nick)
			end
		}
		
		dialog_data.button_list = {
				end_game
		}
	elseif jss.operate_type == 2 then
	    dialog_data.no_buttons = true
	end

	managers.system_menu:show(dialog_data)
	
	if jss.show_modlist then
		local hud = managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)
		self._jss_modlist[id] = hud.panel:panel({
			name = "jss_modlist" .. tostring(id),
			x = 0
		})

		for priority, mod in ipairs(peer:synced_mods()) do
			mod_panel = self._jss_modlist[id]:text({
				name = "mod_panel_" .. tostring(priority),
				color = Color.white,
				text = mod.name,
				y = (priority-1) * 18,
				align = "right",
				layer = 10000,
				font = tweak_data.menu.pd2_large_font,
				font_size = 18
			})
			managers.hud:make_fine_text(mod_panel)
			mod_panel:set_right(self._jss_modlist[id]:w())
		end
	end
	
	if jss.show_player_skill and managers.system_menu._active_dialog then
		local skill_long = peer:skills()
		local skillpoints = string.split(string.split(skill_long, "-")[1], "_")
		local mas_skillpoints = "Mas: " .. skillpoints[1] .. " " .. skillpoints[2] .. " " .. skillpoints[3]
		local enf_skillpoints = "Enf: " .. skillpoints[4] .. " " .. skillpoints[5] .. " " .. skillpoints[6]
		local tec_skillpoints = "Tac: " .. skillpoints[7] .. " " .. skillpoints[8] .. " " .. skillpoints[9]
		local gho_skillpoints = "Gho: " .. skillpoints[10] .. " " .. skillpoints[11] .. " " .. skillpoints[12]
		local fug_skillpoints = "Fug: " .. skillpoints[13] .. " " .. skillpoints[14] .. " " .. skillpoints[15]
		
		local skillpoint_text = mas_skillpoints .. "   " .. enf_skillpoints .. "   " .. tec_skillpoints .. "   " .. gho_skillpoints .. "   " .. fug_skillpoints
		
		local skill_num = 0
		
		for _, sk in ipairs(skillpoints) do
			skill_num = skill_num + tonumber(sk)
		end
		
		local panel = managers.system_menu._active_dialog._ws:panel():children()[1]:children()[6]:children()[3]
		local text_panel_org = panel:children()[2]
			
		local skill_text_panel = panel:text({
			vertical = "top",
			font = tweak_data.hud_players.ammo_font,
			text = skillpoint_text .. " Num: " .. tostring(skill_num),
			font_size = 21,
			x = text_panel_org:left(),
			y = text_panel_org:center_y()
		})
		
		if skill_num > 120 then
			skill_text_panel:set_color(tweak_data.screen_colors.pro_color)
		end
	end
end)

Hooks:PostHook(MenuManager, "update_person_joining", "JoiningScreenSelectorUpdate", function(self, id, progress_percentage)
	local dlg = managers.system_menu:get_dialog("user_dropin" .. id)
	
	if dlg then
		-- managers.mission._fading_debug_output:script().log("updater_jss_peer_id : " .. tostring(id) .. " - " ..tostring(managers.system_menu._active_dialog:id()), Color.yellow)
		local peer = managers.network:session():peer(id)
		local msPing = math.floor(peer:qos().ping)
		local dialog_wait = managers.localization:text("dialog_wait")
		local progress = tostring(progress_percentage)

		local dlg_text = dialog_wait .. " " .. progress .. "% " .. msPing .. "ms" ..  "\n"
		dlg:set_text(dlg_text)
	end
end)

Hooks:PostHook(MenuManager, "close_person_joining", "JoiningScreenSelector_ClosePersonJoining", function(self, id)
	managers.hud:updater_jss_peer_id(nil)
	managers.system_menu:close("user_dropin" .. id)
	managers.system_menu:close("jss_end_game_confirm")
	managers.system_menu:close("jss_on_joining_screen_confirm")

	if self._jss_modlist and self._jss_modlist[id] then
		local hud = managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)
		self._jss_modlist[id]:set_visible(false)
		hud.panel:remove(self._jss_modlist[id])
		self._jss_modlist[id] = nil
		
		if not managers.system_menu._active_dialog then
			for _, panel in ipairs(self._jss_modlist) do
				panel:set_visible(false)
				hud.panel:remove(panel)
			end
			
			self._jss_modlist = nil
		end
	end
end)