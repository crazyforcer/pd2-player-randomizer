_G.Randomizer = Randomizer or {}
Randomizer.data = Randomizer.data or {}
Randomizer.save_path = SavePath
Randomizer.mod_path = ModPath

function Randomizer:save()
  local file = io.open(self.save_path .. "player_randomizer.txt", "w+")
  if file then
    file:write(json.encode(self.data))
    file:close()
  end
end

function Randomizer:load()
  local file = io.open(self.save_path .. "player_randomizer.txt", "r")
  if file then
    self.data = json.decode(file:read("*all"))
    file:close()
  end
end

function Randomizer:allow_randomizing()
  return Utils:IsInGameState()
end

function Randomizer:is_randomized(selection)
  local mapping = {
    [1] = self.data.random_primary,
    [2] = self.data.random_secondary,
    [3] = self.data.random_melee,
    [4] = self.data.random_grenade,
    [5] = self.data.random_armor,
    [6] = self.data.random_deployable
  }
  return mapping[selection]
end

function Randomizer:get_loadout_item_index()
  self._loadout_item_index = self._loadout_item_index or 0
  self._loadout_item_index = self._loadout_item_index + 1
  return self._loadout_item_index
end

function Randomizer:update_outfit()
  if managers.network and managers.network:session() and managers.network:session():local_peer() then
    managers.network:session():local_peer():set_outfit_string(managers.blackmarket:outfit_string())
    if Randomizer.data.random_character then
      managers.network:session():local_peer():set_character(managers.blackmarket:equipped_character())
      managers.network:session():check_send_outfit()
    end
  end
end

function Randomizer:chk_setup_weapons()
  if not self.weapons then
    self.weapons = {}
    for weapon, data in pairs(tweak_data.weapon) do
      if data.autohit then
        local unlocked = managers.blackmarket:weapon_unlocked(weapon) and (not data.global_value or managers.dlc:is_dlc_unlocked(data.global_value))
        if unlocked then
          local selection_index = data.use_data.selection_index
          self.weapons[selection_index] = self.weapons[selection_index] or {}
          local data = {
            selection_index = selection_index,
            weapon_id = weapon,
            factory_id = managers.weapon_factory:get_factory_id_by_weapon_id(weapon),
            equipped = true
          }
          table.insert(self.weapons[selection_index], data)
        end
      end
    end
  end
end

function Randomizer:get_random_weapon(selection_index)
  self:chk_setup_weapons()
  self._random_weapon = self._random_weapon or {}
  if not self._random_weapon[selection_index] then
    local data = self.weapons[selection_index][math.random(#self.weapons[selection_index])]
    data.blueprint = {}
    local has_part_of_type = {}
    local is_forbidden = {}
    local parts = deep_clone(tweak_data.weapon.factory[data.factory_id].uses_parts)
    local must_use = {}
    for _, part_name in ipairs(tweak_data.weapon.factory[data.factory_id].default_blueprint) do
      local part_type = tweak_data.weapon.factory.parts[part_name].type
      must_use[part_type] = true
    end   
    while #parts > 0 do
      local index = math.random(#parts)
      local part_name = parts[index]
      local part = tweak_data.weapon.factory.parts[part_name]
      if part and not part.unatainable and not has_part_of_type[part.type] and not is_forbidden[part_name] and (not part.dlc or managers.dlc:is_dlc_unlocked(part.dlc)) then
        local skip_chance = not must_use[part.type] and math.random() or 100
        local skip_part_type = part.type == "custom" and skip_chance <= 0.7 or part.type == "ammo" and skip_chance <= 0.4 or skip_chance <= 0.2
        if not skip_part_type then
          table.insert(data.blueprint, part_name)
          for _, p in ipairs(part.forbids or {}) do
            is_forbidden[p] = true
          end
        end
        has_part_of_type[part.type] = true
      end
      table.remove(parts, index)
    end
    self._random_weapon[selection_index] = data
  end
  return self._random_weapon[selection_index]
end

function Randomizer:chk_setup_weapons_owned()
  if not self.weapons_owned then
    self.weapons_owned = { {}, {} }
    for slot, data in pairs(Global.blackmarket_manager.crafted_items["primaries"]) do
      local unlocked = managers.blackmarket:weapon_unlocked_by_crafted("primaries", slot)
      if unlocked then
        table.insert(self.weapons_owned[2], data)
      end
    end
    for slot, data in pairs(Global.blackmarket_manager.crafted_items["secondaries"]) do
      local unlocked = managers.blackmarket:weapon_unlocked_by_crafted("secondaries", slot)
      if unlocked then
        table.insert(self.weapons_owned[1], data)
      end
    end
  end
end

function Randomizer:get_random_weapon_owned(selection_index)
  self:chk_setup_weapons_owned()
  self._random_weapon_owned = self._random_weapon_owned or {}
  self._random_weapon_owned[selection_index] = self._random_weapon_owned[selection_index] or self.weapons_owned[selection_index][math.random(#self.weapons_owned[selection_index])]
  return self._random_weapon_owned[selection_index]
end

function Randomizer:chk_setup_grenades()
  if not self.grenades then
    self.grenades = {}
    for grenade_id, data in pairs(tweak_data.blackmarket.projectiles) do
      if data.throwable or data.ability then
        local unlocked = Global.blackmarket_manager.grenades[grenade_id].unlocked and (not data.dlc or managers.dlc:is_dlc_unlocked(data.dlc))
        if unlocked then
          table.insert(self.grenades, grenade_id)
        end
      end
    end
  end
end

function Randomizer:get_random_grenade()
  self:chk_setup_grenades()
  self._random_grenade = self._random_grenade or self.grenades[math.random(#self.grenades)]
  return self._random_grenade
end

function Randomizer:chk_setup_melees()
  if not self.melees then
    self.melees = {}
    for melee_weapon, data in pairs(tweak_data.blackmarket.melee_weapons) do
      local unlocked = Global.blackmarket_manager.melee_weapons[melee_weapon].unlocked and (not data.dlc or managers.dlc:is_dlc_unlocked(data.dlc))
      if unlocked then
        table.insert(self.melees, melee_weapon)
      end
    end
  end
end

function Randomizer:get_random_melee()
  self:chk_setup_melees()
  self._random_melee = self._random_melee or self.melees[math.random(#self.melees)]
  return self._random_melee
end

function Randomizer:chk_setup_armors()
  if not self.armors then
    self.armors = {}
    for armor, _ in pairs(tweak_data.blackmarket.armors) do
      local unlocked = Global.blackmarket_manager.armors[armor].unlocked
      if unlocked then
        table.insert(self.armors, armor)
      end
    end
  end
end

function Randomizer:get_random_armor()
  self:chk_setup_armors()
  self._random_armor = self._random_armor or self.armors[math.random(#self.armors)]
  return self._random_armor
end

function Randomizer:chk_setup_deployables()
  if not self.deployables then
    self.deployables = {}
    for deployable, data in pairs(tweak_data.equipments) do
      if data.visual_object then
        table.insert(self.deployables, deployable)
      end
    end
  end
end

function Randomizer:get_random_deployable()
  self:chk_setup_deployables()
  self._random_deployable = self._random_deployable or self.deployables[math.random(#self.deployables)]
  return self._random_deployable
end

function Randomizer:chk_setup_characters()
  if not self.characters then
    self.characters = {}
    local in_use = {}
    for peer_id, peer in ipairs(managers.network and managers.network:session() and managers.network:session():all_peers() or {}) do
      if peer_id ~= managers.network:session():local_peer():id() then
        in_use[peer:character()] = true
      end
    end
    for character, data in pairs(tweak_data.blackmarket.characters) do
      if character ~= "locked" then
        local unlocked = not data.dlc or managers.dlc:is_dlc_unlocked(data.dlc)
        if data.fps_unit and unlocked and not in_use[character] then
          table.insert(self.characters, character)
        end
      else
        for locked_character, locked_data in pairs(data) do
          if type(locked_data) == "table" then
            local unlocked = not locked_data.dlc or managers.dlc:is_dlc_unlocked(locked_data.dlc)
            if unlocked and not in_use[character] then
              table.insert(self.characters, locked_character)
            end
          end
        end
      end
    end
  end
end

function Randomizer:get_random_character()
  self:chk_setup_characters()
  self._random_character = self._random_character or self.characters[math.random(#self.characters)]
  return self._random_character
end

------------------------ MOD STUFF ------------------------
if RequiredScript == "lib/managers/blackmarketmanager" then
  
  local forced_primary_original = BlackMarketManager.forced_primary
  function BlackMarketManager:forced_primary(...)
    if not Randomizer.data.random_primary or not Randomizer:allow_randomizing() then
      return forced_primary_original(self, ...)
    end
    return Randomizer.data.only_owned_weapons and Randomizer:get_random_weapon_owned(2) or Randomizer:get_random_weapon(2)
  end

  local forced_secondary_original = BlackMarketManager.forced_secondary
  function BlackMarketManager:forced_secondary(...)
    if not Randomizer.data.random_secondary or not Randomizer:allow_randomizing() then
      return forced_secondary_original(self, ...)
    end
    return Randomizer.data.only_owned_weapons and Randomizer:get_random_weapon_owned(1) or Randomizer:get_random_weapon(1)
  end

  local forced_throwable_original = BlackMarketManager.forced_throwable
  function BlackMarketManager:forced_throwable(...)
    if not Randomizer.data.random_grenade or not Randomizer:allow_randomizing() then
      return forced_throwable_original(self, ...)
    end
    return Randomizer:get_random_grenade()
  end

  local equipped_melee_weapon_original = BlackMarketManager.equipped_melee_weapon
  function BlackMarketManager:equipped_melee_weapon(...)
    local forced_melee_weapon = self:forced_melee_weapon()
    if forced_melee_weapon then
      return forced_melee_weapon
    end
    return equipped_melee_weapon_original(self, ...)
  end
  
  function BlackMarketManager:forced_melee_weapon(...)
    if not Randomizer.data.random_melee or not Randomizer:allow_randomizing() then
      return
    end
    return Randomizer:get_random_melee()
  end
  
  local forced_armor_original = BlackMarketManager.forced_armor
  function BlackMarketManager:forced_armor(...)
    if not Randomizer.data.random_armor or not Randomizer:allow_randomizing() then
      return forced_armor_original(self, ...)
    end
    return Randomizer:get_random_armor()
  end
  
  local forced_deployable_original = BlackMarketManager.forced_deployable
  function BlackMarketManager:forced_deployable(...)
    if not Randomizer.data.random_deployable or not Randomizer:allow_randomizing() then
      return forced_deployable_original(self, ...)
    end
    return Randomizer:get_random_deployable()
  end
  
  local forced_character_original = BlackMarketManager.forced_character
  function BlackMarketManager:forced_character(...)
    if not Randomizer.data.random_character or not Randomizer:allow_randomizing() then
      return forced_character_original(self, ...)
    end
    return Randomizer:get_random_character()
  end
  
end

--------------------------- GUI STUFF --------------------------
if RequiredScript == "lib/managers/menu/missionbriefinggui" then

  local init_mission_briefing_gui_original = MissionBriefingGui.init
  function MissionBriefingGui:init(...)
    init_mission_briefing_gui_original(self, ...)
    Randomizer:update_outfit()
  end

  local init_loadout_tab_original = NewLoadoutTab.init
  function NewLoadoutTab:init(...)
    init_loadout_tab_original(self, ...)
    Randomizer._loadout_item_index = 0
  end

  local init_loadout_item_original = NewLoadoutItem.init
  function NewLoadoutItem:init(...)
    init_loadout_item_original(self, ...)
    if Randomizer:is_randomized(Randomizer:get_loadout_item_index()) then
      if Randomizer.data.hide_selections then
        if self._info_icon_panel then
          self._info_icon_panel:set_alpha(0)
        end
        self._info_text:set_alpha(0)
        local questionmark = self._item_panel:text({
          name = "questionmark",
          text = "?",
          font = tweak_data.menu.eroded_font,
          font_size = 140,
          align = "center",
          vertical = "center",
          color = Color.black
        })
        questionmark:set_center(self._item_panel:center_x(), self._item_panel:center_y() + 8)
      end
      if self._item_image then
        self._item_image:set_color(Color.black:with_alpha(Randomizer.data.hide_selections and 0 or 1))
      end
      if self._item_image1 then
        self._item_image1:set_color(Color.black:with_alpha(Randomizer.data.hide_selections and 0 or 1))
      end
      if self._item_image2 then
        self._item_image2:set_color(Color.black:with_alpha(Randomizer.data.hide_selections and 0 or 1))
      end
      local lock = self._item_panel:bitmap({
        name = "lock",
        texture = "guis/textures/pd2/skilltree/padlock",
        w = 32,
        h = 32,
        color = tweak_data.screen_colors.text,
        layer = 2
      })
      lock:set_center(self._item_panel:center_x(), self._item_panel:center_y())
    end
  end
  
  local set_slot_outfit_original = TeamLoadoutItem.set_slot_outfit
  function TeamLoadoutItem:set_slot_outfit(slot, criminal_name, outfit, ...)
    local peer_id = managers.network and managers.network:session() and managers.network:session():local_peer():id() or 1
    if slot ~= peer_id or not outfit or not Randomizer.data.hide_selections then
      return set_slot_outfit_original(self, slot, criminal_name, outfit, ...)
    end
    local new_outfit = deep_clone(outfit)
    new_outfit.primary.factory_id = not Randomizer.data.random_primary and new_outfit.primary.factory_id
    new_outfit.secondary.factory_id = not Randomizer.data.random_secondary and new_outfit.secondary.factory_id
    new_outfit.melee_weapon = not Randomizer.data.random_melee and new_outfit.melee_weapon
    new_outfit.grenade = not Randomizer.data.random_grenade and new_outfit.grenade
    new_outfit.armor = not Randomizer.data.random_armor and new_outfit.armor
    new_outfit.deployable = not Randomizer.data.random_deployable and new_outfit.deployable
    return set_slot_outfit_original(self, slot, criminal_name, new_outfit, ...)
  end
  
  local confirm_pressed_original = NewLoadoutTab.confirm_pressed
  function NewLoadoutTab:confirm_pressed(...)
    if Randomizer:is_randomized(self._item_selected) then
      return
    end
    return confirm_pressed_original(self, ...)
  end
  
end

-------------------- MENU STUFF --------------------
if RequiredScript == "lib/managers/menumanager" then

  Hooks:Add("LocalizationManagerPostInit", "LocalizationManagerPostInitPlayerRandomizer", function(loc)
    loc:load_localization_file(Randomizer.mod_path .. "loc/english.txt")
    for _, filename in pairs(file.GetFiles(Randomizer.mod_path .. "loc/")) do
      local str = filename:match('^(.*).txt$')
      if str and Idstring(str) and Idstring(str):key() == SystemInfo:language():key() then
        loc:load_localization_file(Randomizer.mod_path .. "loc/" .. filename)
        break
      end
    end
  end)

  local menu_id_main = "PlayerRandomizerMenu"
  Hooks:Add("MenuManagerSetupCustomMenus", "MenuManagerSetupCustomMenusPlayerRandomizer", function(menu_manager, nodes)
    MenuHelper:NewMenu(menu_id_main)
  end)

  Hooks:Add("MenuManagerPopulateCustomMenus", "MenuManagerPopulateCustomMenusPlayerRandomizer", function(menu_manager, nodes)
    
    Randomizer:load()
    
    MenuCallbackHandler.Randomizer_toggle = function(self, item)
      Randomizer.data[item:name()] = (item:value() == "on");
      Randomizer:update_outfit()
      Randomizer:save()
    end

    MenuHelper:AddToggle({
      id = "hide_selections",
      title = "hide_selections_name",
      desc = "hide_selections_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.hide_selections,
      menu_id = menu_id_main,
      priority = 12
    })
    MenuHelper:AddToggle({
      id = "only_owned_weapons",
      title = "only_owned_weapons_name",
      desc = "only_owned_weapons_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.only_owned_weapons,
      menu_id = menu_id_main,
      priority = 11
    })
    MenuHelper:AddDivider({
      id = "divider",
      size = 24,
      menu_id = menu_id_main,
      priority = 10
    })
    MenuHelper:AddToggle({
      id = "random_character",
      title = "bm_menu_characters",
      desc = "character_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.random_character,
      menu_id = menu_id_main,
      priority = 7
    })
    MenuHelper:AddToggle({
      id = "random_primary",
      title = "bm_menu_primaries",
      desc = "primary_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.random_primary,
      menu_id = menu_id_main,
      priority = 6
    })
    MenuHelper:AddToggle({
      id = "random_secondary",
      title = "bm_menu_secondaries",
      desc = "secondary_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.random_secondary,
      menu_id = menu_id_main,
      priority = 5
    })
    MenuHelper:AddToggle({
      id = "random_melee",
      title = "bm_menu_melee_weapons",
      desc = "melee_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.random_melee,
      menu_id = menu_id_main,
      priority = 4
    })
    MenuHelper:AddToggle({
      id = "random_grenade",
      title = "bm_menu_grenades",
      desc = "grenade_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.random_grenade,
      menu_id = menu_id_main,
      priority = 3
    })
    MenuHelper:AddToggle({
      id = "random_armor",
      title = "bm_menu_armor",
      desc = "armor_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.random_armor,
      menu_id = menu_id_main,
      priority = 2
    })
    MenuHelper:AddToggle({
      id = "random_deployable",
      title = "bm_menu_deployables",
      desc = "deployable_desc",
      callback = "Randomizer_toggle",
      value = Randomizer.data.random_deployable,
      menu_id = menu_id_main,
      priority = 1
    })
    
  end)

  Hooks:Add("MenuManagerBuildCustomMenus", "MenuManagerBuildCustomMenusPlayerRandomizer", function(menu_manager, nodes)
    nodes[menu_id_main] = MenuHelper:BuildMenu(menu_id_main)
    MenuHelper:AddMenuItem(MenuHelper:GetMenu("lua_mod_options_menu"), menu_id_main, "Randomizer_menu_main_name", "Randomizer_menu_main_desc")
  end)

end