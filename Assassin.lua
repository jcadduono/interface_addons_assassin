local ADDON = 'Assassin'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_ASSASSIN = ADDON
BINDING_NAME_ASSASSIN_TARGETMORE = "Toggle Targets +"
BINDING_NAME_ASSASSIN_TARGETLESS = "Toggle Targets -"
BINDING_NAME_ASSASSIN_TARGET1 = "Set Targets to 1"
BINDING_NAME_ASSASSIN_TARGET2 = "Set Targets to 2"
BINDING_NAME_ASSASSIN_TARGET3 = "Set Targets to 3"
BINDING_NAME_ASSASSIN_TARGET4 = "Set Targets to 4"
BINDING_NAME_ASSASSIN_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'ROGUE' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetActionInfo = _G.GetActionInfo
local GetBindingKey = _G.GetBindingKey
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return uid and tonumber(uid)
end
-- end useful functions

Assassin = {}
local Opt -- use this as a local table reference to Assassin

SLASH_Assassin1, SLASH_Assassin2 = '/ass', '/assassin'

local function InitOpts()
	local function SetDefaults(t, ref)
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Assassin, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			animation = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			assassination = false,
			outlaw = false,
			subtlety = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		keybinds = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 8,
		pot = false,
		trinket = true,
		heal = 60,
		multipliers = true,
		poisons = true,
		poison_priority = {
			lethal = {},
			nonlethal = {},
		},
		priority_rotation = false,
		vanish_solo = false,
		rtb_values = {
			enabled = false,
			broadside = 10,
			true_bearing = 11,
			ruthless_precision = 9,
			skull_and_crossbones = 8,
			buried_treasure = 4,
			grand_melee = 3,
			grand_melee_aoe = 2,
			threshold = 16,
			loaded_dice = 7,
		},
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	buttons = {},
	action_slots = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	tracked = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- methods for tracking ticking debuffs on targets
local TrackedAuras = {}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	ASSASSINATION = 1,
	OUTLAW = 2,
	SUBTLETY = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.ASSASSINATION] = {},
	[SPEC.OUTLAW] = {},
	[SPEC.SUBTLETY] = {},
}

-- current player information
local Player = {
	initialized = false,
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	energy = {
		current = 0,
		max = 100,
		deficit = 100,
		pct = 0,
		regen = 0,
	},
	combo_points = {
		current = 0,
		max = 5,
		deficit = 5,
		max_spend = 5,
		effective = 0,
		supercharged = {},
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		mh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
	},
	set_bonus = {
		t33 = 0, -- K'areshi Phantom's Bindings
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	poison = {
		lethal = {},
		nonlethal = {},
	},
	stealthed = false,
	stealthed_nomeld = false,
	stealth_time = 0,
	stealth_remains = 0,
	danse_stacks = 0,
}

-- current target information
local Target = {
	boss = false,
	dummy = false,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
	[219250] = true,
	[225983] = true,
	[225984] = true,
	[225985] = true,
	[225976] = true,
	[225977] = true,
	[225978] = true,
	[225982] = true,
}

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.ASSASSINATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.OUTLAW] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.SUBTLETY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5'},
		{6, '6'},
		{7, '7+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	assassinPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Assassin_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Assassin_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Assassin_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local uid = ToUID(guid)
	if uid and self.ignored_units[uid] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function AutoAoe:Purge()
	local update
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		energy_cost = 0,
		cp_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
		keybinds = {},
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self.Available and not self:Available(seconds) then
		return false
	end
	if not pool and self:EnergyCost() > Player.energy.current then
		return false
	end
	if self:CPCost() > Player.combo_points.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:React()
	return self:Remains()
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:MaxStack()
	return self.max_stack
end

function Ability:Capped(deficit)
	return self:Stack() >= (self:MaxStack() - (deficit or 0))
end

function Ability:EnergyCost()
	return self.energy_cost
end

function Ability:CPCost()
	return self.cp_cost
end

function Ability:Free()
	return (
		(self.energy_cost > 0 and self:EnergyCost() == 0) or
		(self.cp_cost > 0 and self:CPCost() == 0)
	)
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
end

function Ability:CastEnergyRegen()
	return Player.energy.regen * self:CastTime() - self:EnergyCost()
end

function Ability:WontCapEnergy(reduction)
	return (Player.energy.current + self:CastEnergyRegen()) < (Player.energy.max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		assassinPreviousPanel.ability = self
		assassinPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		assassinPreviousPanel.icon:SetTexture(self.icon)
		assassinPreviousPanel:SetShown(assassinPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and assassinPreviousPanel.ability == self then
		assassinPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

function TrackedAuras:Purge()
	for _, ability in next, Abilities.tracked do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function TrackedAuras:Remove(guid)
	for _, ability in next, Abilities.tracked do
		ability:RemoveAura(guid)
	end
end

function Ability:Track()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration(self.next_combo_points, self.next_applied_by)
	if self.next_multiplier then
		aura.multiplier = self.next_multiplier
	end
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration(self.next_combo_points, self.next_applied_by)
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	if self.next_multiplier and (
		not self.retain_higher_multiplier or
		not aura.multiplier or
		self.next_multiplier > aura.multiplier
	) then
		aura.multiplier = self.next_multiplier
	end
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration(self.next_combo_points, self.next_applied_by)
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
		if self.next_multiplier and (
			not self.retain_higher_multiplier or
			not aura.multiplier or
			self.next_multiplier > aura.multiplier
		) then
			aura.multiplier = self.next_multiplier
		end
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

function Ability:Multiplier(guid)
	local aura = self.aura_targets[guid or Target.guid]
	return aura and aura.multiplier or 0
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFoci()[1]:GetNodeID()
]]

-- Rogue Abilities
---- Class
------ Baseline
local Ambush = Ability:Add(8676, false, true)
Ambush.energy_cost = 50
local CheapShot = Ability:Add(1833, false, true)
CheapShot.buff_duration = 4
CheapShot.energy_cost = 40
local CrimsonVial = Ability:Add(185311, true, true)
CrimsonVial.buff_duration = 4
CrimsonVial.cooldown_duration = 30
CrimsonVial.energy_cost = 20
local Eviscerate = Ability:Add(196819, false, true)
Eviscerate.energy_cost = 35
Eviscerate.cp_cost = 1
Eviscerate.next_combo_points = 0
local Kick = Ability:Add(1766, false, true)
Kick.cooldown_duration = 15
Kick.triggers_gcd = false
Kick.off_gcd = true
local KidneyShot = Ability:Add(408, false, true)
KidneyShot.buff_duration = 1
KidneyShot.energy_cost = 25
KidneyShot.cp_cost = 1
KidneyShot.next_combo_points = 0
local Rupture = Ability:Add(1943, false, true)
Rupture.buff_duration = 4
Rupture.energy_cost = 25
Rupture.cp_cost = 1
Rupture.next_combo_points = 0
Rupture.tick_interval = 2
Rupture.hasted_ticks = true
Rupture:Track()
Rupture:AutoAoe(false, 'apply')
local ShadowDance = Ability:Add(185313, true, true, 185422)
ShadowDance.buff_duration = 6
ShadowDance.cooldown_duration = 60
ShadowDance.requires_charge = true
ShadowDance.triggers_gcd = false
ShadowDance.off_gcd = true
local SinisterStrike = Ability:Add(193315, false, true)
SinisterStrike.energy_cost = 45
local SliceAndDice = Ability:Add(315496, true, true)
SliceAndDice.buff_duration = 6
SliceAndDice.energy_cost = 25
SliceAndDice.cp_cost = 1
SliceAndDice.next_combo_points = 0
local Stealth = Ability:Add(1784, true, true, 115191)
local Vanish = Ability:Add(1856, true, true, 11327)
Vanish.cooldown_duration = 120
Vanish.requires_charge = true
Vanish.triggers_gcd = false
Vanish.off_gcd = true
------ Talents
local Alacrity = Ability:Add(193539, true, true)
Alacrity.buff_duration = 20
local ColdBlood = Ability:Add(382245, true, true)
ColdBlood.buff_duration = 600
ColdBlood.cooldown_duration = 45
ColdBlood.triggers_gcd = false
ColdBlood.off_gcd = true
local DeeperStratagem = Ability:Add(193531, false, true)
local FindWeakness = Ability:Add(91023, false, true, 316220)
FindWeakness.buff_duration = 10
local ForcedInduction = Ability:Add(470668, false, true)
local Gouge = Ability:Add(1776, false, true)
Gouge.buff_duration = 4
Gouge.cooldown_duration = 15
Gouge.energy_cost = 25
local ImprovedAmbush = Ability:Add(381620, false, true)
local Nightstalker = Ability:Add(14062, false, true)
local ResoundingClarity = Ability:Add(381622, true, true)
local SealFate = Ability:Add(14190, true, true, 14189)
SealFate.talent_node = 90757
local Shiv = Ability:Add(5938, false, true, 319504)
Shiv.buff_duration = 8
Shiv.cooldown_duration = 30
Shiv.energy_cost = 30
Shiv.requires_charge = true
local Subterfuge = Ability:Add(108208, true, true, 115192)
Subterfuge.buff_duration = 3
Subterfuge.talent_node = 90688
local Supercharger = Ability:Add(470347, true, true)
Supercharger[1] = Ability:Add(470398, true, true)
Supercharger[2] = Ability:Add(470406, true, true)
Supercharger[3] = Ability:Add(470409, true, true)
Supercharger[4] = Ability:Add(470412, true, true)
Supercharger[5] = Ability:Add(470414, true, true)
Supercharger[6] = Ability:Add(470415, true, true)
Supercharger[7] = Ability:Add(470416, true, true)
local ThistleTea = Ability:Add(381623, true, true)
ThistleTea.buff_duration = 6
ThistleTea.cooldown_duration = 60
ThistleTea.requires_charge = true
ThistleTea.triggers_gcd = false
ThistleTea.off_gcd = true
local TightSpender = Ability:Add(381621, true, true)
local Vigor = Ability:Add(14983, false, true)
local VirulentPoisons = Ability:Add(381543, true, true)
local Weaponmaster = Ability:Add({193537, 200733}, false, true)
------ Procs

------ Poisons
local Poison = {}
Poison.Amplifying = Ability:Add(381664, true, true)
Poison.Amplifying.buff_duration = 3600
Poison.Amplifying.lethal = true
Poison.Amplifying.DoT = Ability:Add(383414, false, true)
Poison.Amplifying.DoT.buff_duration = 12
Poison.Amplifying.DoT.max_stack = 20
Poison.Amplifying.DoT:Track()
Poison.Atrophic = Ability:Add(381637, true, true)
Poison.Atrophic.buff_duration = 3600
Poison.Atrophic.nonlethal = true
Poison.Atrophic.DoT = Ability:Add(392388)
Poison.Atrophic.DoT.buff_duration = 10
Poison.Crippling = Ability:Add(3408, true, true)
Poison.Crippling.buff_duration = 3600
Poison.Crippling.nonlethal = true
Poison.Crippling.DoT = Ability:Add(3409)
Poison.Crippling.DoT.buff_duration = 12
Poison.Deadly = Ability:Add(2823, true, true)
Poison.Deadly.buff_duration = 3600
Poison.Deadly.lethal = true
Poison.Deadly.DoT = Ability:Add(2818, false, true)
Poison.Deadly.DoT.buff_duration = 12
Poison.Deadly.DoT.tick_interval = 2
Poison.Deadly.DoT.hasted_ticks = true
Poison.Deadly.DoT:Track()
Poison.Instant = Ability:Add(315584, true, true)
Poison.Instant.buff_duration = 3600
Poison.Instant.lethal = true
Poison.Numbing = Ability:Add(5761, true, true)
Poison.Numbing.buff_duration = 3600
Poison.Numbing.nonlethal = true
Poison.Numbing.DoT = Ability:Add(5760)
Poison.Numbing.DoT.buff_duration = 10
Poison.Wound = Ability:Add(8679, true, true)
Poison.Wound.buff_duration = 3600
Poison.Wound.lethal = true
Poison.Wound.DoT = Ability:Add(8680, false, true)
Poison.Wound.DoT.buff_duration = 12
Poison.Wound.DoT:Track()
---- Assassination
local Envenom = Ability:Add(32645, true, true)
Envenom.buff_duration = 0
Envenom.energy_cost = 35
Envenom.cp_cost = 1
Envenom.next_combo_points = 0
Envenom.max_stack = 1
local FanOfKnives = Ability:Add(51723, false, true)
FanOfKnives.energy_cost = 35
FanOfKnives:AutoAoe(true)
local Garrote = Ability:Add(703, false, true)
Garrote.buff_duration = 18
Garrote.cooldown_duration = 6
Garrote.energy_cost = 45
Garrote.tick_interval = 2
Garrote.hasted_ticks = true
Garrote:Track()
local Mutilate = Ability:Add(1329, false, true)
Mutilate.energy_cost = 50
------ Talents
local ArterialPrecision = Ability:Add(400783, false, true)
local Blindside = Ability:Add(328085, true, true, 121153)
Blindside.buff_duration = 10
Blindside.max_stack = 1
local CausticSpatter = Ability:Add(421975, false, true, 421976)
CausticSpatter.buff_duration = 10
CausticSpatter.Splash = Ability:Add(421979, false, true)
CausticSpatter.Splash:AutoAoe()
local CrimsonTempest = Ability:Add(121411, false, true)
CrimsonTempest.buff_duration = 4
CrimsonTempest.energy_cost = 45
CrimsonTempest.cp_cost = 1
CrimsonTempest.next_combo_points = 0
CrimsonTempest.tick_interval = 2
CrimsonTempest.hasted_ticks = true
CrimsonTempest:Track()
CrimsonTempest:AutoAoe(false, 'apply')
local DashingScoundrel = Ability:Add(381797, true, true)
local Deathmark = Ability:Add(360194, false, true)
Deathmark.buff_duration = 16
Deathmark.cooldown_duration = 120
Deathmark:Track()
local DragonTemperedBlades = Ability:Add(381801, true, true)
local ImprovedGarrote = Ability:Add(381632, true, true, 392403)
ImprovedGarrote.Fading = Ability:Add(392401, true, true)
ImprovedGarrote.Fading.buff_duration = 6
local IndiscriminateCarnage = Ability:Add(381802, true, true, 385754)
IndiscriminateCarnage.Fading = Ability:Add(385747, true, true)
IndiscriminateCarnage.Fading.buff_duration = 6
local Kingsbane = Ability:Add(385627, false, true)
Kingsbane.buff_duration = 14
Kingsbane.cooldown_duration = 60
Kingsbane.energy_cost = 35
Kingsbane:Track()
Kingsbane.Buff = Ability:Add(394095, true, true)
Kingsbane.Buff.buff_duration = 14
local LightweightShiv = Ability:Add(394983, false, true)
local MasterAssassin = Ability:Add(255989, true, true, 256735)
MasterAssassin.Fading = Ability:Add(470676, true, true)
MasterAssassin.Fading.buff_duration = 6
local SanguineStratagem = Ability:Add(457512, true, true)
local ScentOfBlood = Ability:Add(381799, true, true, 394080)
ScentOfBlood.buff_duration = 24
ScentOfBlood.max_stack = 20
ScentOfBlood.talent_node = 90775
local ShroudedSuffocation = Ability:Add(385478, false, true)
local SerratedBoneSpike = Ability:Add(455352, true, true, 455366)
SerratedBoneSpike.buff_duration = 3600
SerratedBoneSpike.max_stack = 3
SerratedBoneSpike.DoT = Ability:Add(394036, false, true)
SerratedBoneSpike.DoT.buff_duration = 3600
SerratedBoneSpike.DoT.tick_interval = 3
SerratedBoneSpike.DoT.hasted_ticks = true
local TinyToxicBlade = Ability:Add(381800, true, true)
local ThrownPrecision = Ability:Add(381629, false, true)
local ToxicBlade = Ability:Add(245388, false, true, 245389)
ToxicBlade.buff_duration = 9
ToxicBlade.cooldown_duration = 25
ToxicBlade.energy_cost = 20
local ViciousVenoms = Ability:Add(381634, false, true)
ViciousVenoms.talent_node = 90772
------ Procs

---- Outlaw
local AdrenalineRush = Ability:Add(13750, true, true)
AdrenalineRush.buff_duration = 20
AdrenalineRush.cooldown_duration = 180
AdrenalineRush.triggers_gcd = false
AdrenalineRush.off_gcd = true
local BetweenTheEyes = Ability:Add(315341, true, true)
BetweenTheEyes.buff_duration = 3
BetweenTheEyes.cooldown_duration = 45
BetweenTheEyes.energy_cost = 25
BetweenTheEyes.cp_cost = 1
BetweenTheEyes.next_combo_points = 0
local BladeFlurry = Ability:Add(13877, true, true)
BladeFlurry.cooldown_duration = 30
BladeFlurry.buff_duration = 12
BladeFlurry.Cleave = Ability:Add(22482, false, true)
BladeFlurry.Cleave:AutoAoe()
local Dispatch = Ability:Add(2098, false, true)
Dispatch.energy_cost = 35
Dispatch.cp_cost = 1
Dispatch.next_combo_points = 0
local PistolShot = Ability:Add(185763, false, true)
PistolShot.buff_duration = 6
PistolShot.energy_cost = 40
local RollTheBones = Ability:Add(315508, true, true)
RollTheBones.buff_duration = 30
RollTheBones.cooldown_duration = 45
RollTheBones.energy_cost = 25
------ Talents
local Audacity = Ability:Add(381845, true, true, 386270)
Audacity.buff_duration = 10
local BladeRush = Ability:Add(271877, false, true, 271881)
BladeRush.cooldown_duration = 45
BladeRush:AutoAoe()
local CountTheOdds = Ability:Add(381982, true, true)
local Crackshot = Ability:Add(423703, false, true)
local DeftManeuvers = Ability:Add(381878, false, true)
local DeviousStratagem = Ability:Add(394321, true, true)
local DirtyTricks = Ability:Add(108216, false, true)
local FanTheHammer = Ability:Add(381846, true, true)
FanTheHammer.talent_node = 90666
local GhostlyStrike = Ability:Add(196937, false, true)
GhostlyStrike.buff_duration = 10
GhostlyStrike.cooldown_duration = 35
GhostlyStrike.energy_cost = 30
local GreenskinsWickers = Ability:Add(386823, true, true, 394131)
GreenskinsWickers.buff_duration = 15
local HiddenOpportunity = Ability:Add(383281, false, true)
local ImprovedAdrenalineRush = Ability:Add(395422, true, true, 395424)
local ImprovedBetweenTheEyes = Ability:Add(235484, false, true)
local KeepItRolling = Ability:Add(381989, true, true)
KeepItRolling.buff_duration = 30
KeepItRolling.cooldown_duration = 420
local KillingSpree = Ability:Add(51690, false, true)
KillingSpree.cooldown_duration = 120
KillingSpree:AutoAoe()
local LoadedDice = Ability:Add(256170, true, true, 256171)
LoadedDice.buff_duration = 45
local QuickDraw = Ability:Add(196938, true, true)
local SummarilyDispatched = Ability:Add(381990, true, true, 386868)
SummarilyDispatched.talent_node = 90653
SummarilyDispatched.buff_duration = 8
local SwiftSlasher = Ability:Add(381988, true, true)
local UnderhandedUpperHand = Ability:Add(424044, false, true)
------ Procs
Opportunity = Ability:Add(279876, true, true, 195627)
Opportunity.buff_duration = 10
RollTheBones.Broadside = Ability:Add(193356, true, true)
RollTheBones.Broadside.buff_duration = 30
RollTheBones.BuriedTreasure = Ability:Add(199600, true, true)
RollTheBones.BuriedTreasure.buff_duration = 30
RollTheBones.GrandMelee = Ability:Add(193358, true, true)
RollTheBones.GrandMelee.buff_duration = 30
RollTheBones.RuthlessPrecision = Ability:Add(193357, true, true)
RollTheBones.RuthlessPrecision.buff_duration = 30
RollTheBones.SkullAndCrossbones = Ability:Add(199603, true, true)
RollTheBones.SkullAndCrossbones.buff_duration = 30
RollTheBones.TrueBearing = Ability:Add(193359, true, true)
RollTheBones.TrueBearing.buff_duration = 30
RollTheBones.Buffs = {
	[RollTheBones.Broadside] = true,
	[RollTheBones.BuriedTreasure] = true,
	[RollTheBones.GrandMelee] = true,
	[RollTheBones.RuthlessPrecision] = true,
	[RollTheBones.SkullAndCrossbones] = true,
	[RollTheBones.TrueBearing] = true,
}
---- Subtlety
local Backstab = Ability:Add(53, false, true)
Backstab.energy_cost = 35
local Shadowstrike = Ability:Add(185438, false, true)
Shadowstrike.energy_cost = 40
local ShadowTechniques = Ability:Add(196912, true, true, 196911)
local ShurikenStorm = Ability:Add(197835, false, true)
ShurikenStorm.energy_cost = 35
ShurikenStorm:AutoAoe(true)
local ShurikenToss = Ability:Add(114014, false, true)
ShurikenToss.energy_cost = 40
local SymbolsOfDeath = Ability:Add(212283, true, true)
SymbolsOfDeath.buff_duration = 10
SymbolsOfDeath.cooldown_duration = 30
SymbolsOfDeath.triggers_gcd = false
SymbolsOfDeath.off_gcd = true
------ Talents
local BlackPowder = Ability:Add(319175, false, true)
BlackPowder.energy_cost = 35
BlackPowder.cp_cost = 1
BlackPowder.next_combo_points = 0
BlackPowder:AutoAoe(true)
local DanseMacabre = Ability:Add(382528, true, true, 393969)
local Gloomblade = Ability:Add(200758, false, true)
Gloomblade.energy_cost = 35
local DarkBrew = Ability:Add(382504, false, true)
local DarkShadow = Ability:Add(245687, false, true)
DarkShadow.talent_node = 90732
local DeathPerception = Ability:Add(469642, false, true)
local DeepeningShadows = Ability:Add(185314, true, true)
local DeeperDaggers = Ability:Add(382517, true, true, 383405)
DeeperDaggers.buff_duration = 8
local Finality = Ability:Add(382525, true, true)
Finality.talent_node = 90720
Finality.BlackPowder = Ability:Add(385948, true, true)
Finality.BlackPowder.buff_duration = 20
Finality.Eviscerate = Ability:Add(385949, true, true)
Finality.Eviscerate.buff_duration = 20
Finality.Rupture = Ability:Add(385951, true, true)
Finality.Rupture.buff_duration = 20
local Flagellation = Ability:Add(384631, false, true)
Flagellation.buff_duration = 12
Flagellation.cooldown_duration = 90
Flagellation.Buff = Ability:Add(384631, true, true)
Flagellation.Buff.buff_duration = 12
Flagellation.Persist = Ability:Add(394758, true, true)
Flagellation.Persist.buff_duration = 12
local GoremawsBite = Ability:Add(426591, false, true, 426592)
GoremawsBite.energy_cost = 25
GoremawsBite.cooldown_duration = 45
GoremawsBite.Buff = Ability:Add(426593, true, true)
GoremawsBite.Buff.buff_duration = 30
GoremawsBite.Buff.max_stack = 3
local ImprovedShurikenStorm = Ability:Add(319951, true, true)
local LingeringShadow = Ability:Add(382524, true, true, 385960)
LingeringShadow.buff_duration = 18
local MasterOfShadows = Ability:Add(196976, true, true, 196980)
MasterOfShadows.buff_duration = 3
local PerforatedVeins = Ability:Add(382518, true, true, 394254)
PerforatedVeins.max_stack = 4
local Premeditation = Ability:Add(343160, true, true, 343173)
Premeditation.max_stack = 1
local ReplicatingShadows = Ability:Add(382506, false, true)
local SecretStratagem = Ability:Add(394320, true, true)
local SecretTechnique = Ability:Add(280719, true, true)
SecretTechnique.cooldown_duration = 60
SecretTechnique.energy_cost = 30
SecretTechnique.cp_cost = 1
SecretTechnique.next_combo_points = 0
SecretTechnique:AutoAoe(true)
local ShadowBlades = Ability:Add(121471, true, true)
ShadowBlades.buff_duration = 16
ShadowBlades.cooldown_duration = 90
ShadowBlades.triggers_gcd = false
ShadowBlades.off_gcd = true
local Shadowcraft = Ability:Add(426594, true, true)
local ShadowFocus = Ability:Add(108209, false, true)
local ShotInTheDark = Ability:Add(257505, true, true, 257506)
ShotInTheDark.max_stack = 1
local ShurikenTornado = Ability:Add(277925, true, true)
ShurikenTornado.energy_cost = 60
ShurikenTornado.buff_duration = 4
ShurikenTornado.cooldown_duration = 60
ShurikenTornado.tick_interval = 1
ShurikenTornado:AutoAoe(true)
local SilentStorm = Ability:Add(385722, true, true, 385727)
local TheRotten = Ability:Add(382015, true, true, 394203)
TheRotten.buff_duration = 30
TheRotten.max_stack = 2
-- Hero talents
---- Deathstalker
local ClearTheWitnesses = Ability:Add(457053, true, true, 457178)
ClearTheWitnesses.buff_duration = 12
ClearTheWitnesses.max_stack = 1
local CorruptTheBlood = Ability:Add(457066, false, true, 457133)
CorruptTheBlood.max_stack = 10
local DarkestNight = Ability:Add(457058, true, true, 457280)
DarkestNight.buff_duration = 30
local DeathstalkersMark = Ability:Add(457052, false, true, 457129)
DeathstalkersMark.buff_duration = 60
DeathstalkersMark.max_stack = 3
local FollowTheBlood = Ability:Add(457068, true, true)
local MomentumOfDespair = Ability:Add(457067, true, true, 457115)
MomentumOfDespair.buff_duration = 12
local LingeringDarkness = Ability:Add(457056, true, true, 457273)
LingeringDarkness.buff_duration = 30
---- Fatebound
local HandOfFate = Ability:Add(452536, true, true)
local LuckyCoin = Ability:Add(452562, true, true)
local FateboundCoin = Ability:Add(452542, false, true)
FateboundCoin.Heads = Ability:Add(452923, true, true)
FateboundCoin.Heads.buff_duration = 15
FateboundCoin.Heads.max_stack = 99
FateboundCoin.Tails = Ability:Add(452917, true, true)
FateboundCoin.Tails.buff_duration = 15
FateboundCoin.Tails.max_stack = 99
---- Trickster
local CoupDeGrace = Ability:Add(441776, false, true)
CoupDeGrace.energy_cost = 35
CoupDeGrace.cp_cost = 1
CoupDeGrace.next_combo_points = 0
CoupDeGrace.learn_spellId = 441423
CoupDeGrace.Buff = Ability:Add(441786, true, true)
CoupDeGrace.Buff.max_stack = 4
local Fazed = Ability:Add(441224, false, true)
Fazed.buff_duration = 10
Fazed.learn_spellId = 441146
Fazed:Track()
local FlawlessForm = Ability:Add(441321, true, true, 441326)
FlawlessForm.buff_duration = 12
FlawlessForm.max_stack = 30
local NimbleFlurry = Ability:Add(441367, false, true, 459497)
NimbleFlurry:AutoAoe()
local UnseenBlade = Ability:Add(441146, false, true, 441144)
-- Tier bonuses

-- PvP talents

-- Racials
local Racial = {}
Racial.ArcaneTorrent = Ability:Add(25046, true, false) -- Blood Elf
Racial.Shadowmeld = Ability:Add(58984, true, true) -- Night Elf
-- Trinket effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, Trinket = {}, {}
InventoryItem.__index = InventoryItem

local InventoryItems = {
	all = {},
	byItemId = {},
}

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
		off_gcd = true,
		keybinds = {},
	}
	setmetatable(item, self)
	InventoryItems.all[#InventoryItems.all + 1] = item
	InventoryItems.byItemId[itemId] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local Healthstone = InventoryItem:Add(5512)
Healthstone.max_charges = 3
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.tracked)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.tracked[#self.tracked + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:EnergyTimeToMax(energy)
	local deficit = (energy or self.energy.max) - self.energy.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.energy.regen
end

function Player:ComboPoints()
	if Supercharger.known and self.combo_points.supercharged[self.combo_points.current] then
		return self.combo_points.current + (ForcedInduction.known and 3 or 2)
	end
	return self.combo_points.current
end

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
	end
	if ShadowTechniques.known and not missed then
		ShadowTechniques.auto_count = ShadowTechniques.auto_count + 1
	end
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 2825 or   -- Bloodlust (Horde Shaman)
			aura.spellId == 32182 or  -- Heroism (Alliance Shaman)
			aura.spellId == 80353 or  -- Time Warp (Mage)
			aura.spellId == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			aura.spellId == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			aura.spellId == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			aura.spellId == 381301 or -- Feral Hide Drums (Leatherworking)
			aura.spellId == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdatePoisons()
	if #Opt.poison_priority.lethal == 0 then
		Poison.Wound:Default()
		Poison.Instant:Default()
		Poison.Amplifying:Default()
		Poison.Deadly:Default()
	end
	if #Opt.poison_priority.nonlethal == 0 then
		Poison.Crippling:Default()
		Poison.Numbing:Default()
		Poison.Atrophic:Default()
	end
	local ability
	table.wipe(self.poison.lethal)
	for _, spellId in next, Opt.poison_priority.lethal do
		ability = Abilities.bySpellId[spellId]
		if ability then
			self.poison.lethal[#self.poison.lethal + 1] = ability
		end
	end
	table.wipe(self.poison.nonlethal)
	for _, spellId in next, Opt.poison_priority.nonlethal do
		ability = Abilities.bySpellId[spellId]
		if ability then
			self.poison.nonlethal[#self.poison.nonlethal + 1] = ability
		end
	end
	if Poison.Amplifying.known then
		Poison.Amplifying:Default()
	end
	if Poison.Deadly.known then
		Poison.Deadly:Default()
	end
end

function Player:UpdateKnown()
	local info, node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			info = GetSpellInfo(spellId)
			if info then
				ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
			end
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsSpellUsable(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	for _, ability in next, Poison do
		if ability.known and ability.DoT then
			ability.DoT.known = true
		end
	end
	if RollTheBones.known then
		for buff in next, RollTheBones.Buffs do
			buff.known = true
		end
	end
	if Supercharger.known then
		for i = 1, 7 do
			Supercharger[i].known = true
		end
	end
	if Gloomblade.known then
		Backstab.known = false
	end
	ShadowTechniques.auto_count = 0
	Kingsbane.Buff.known = Kingsbane.known
	ImprovedGarrote.Fading.known = ImprovedGarrote.known
	IndiscriminateCarnage.Fading.known = IndiscriminateCarnage.known
	MasterAssassin.Fading.known = MasterAssassin.known
	SerratedBoneSpike.DoT.known = SerratedBoneSpike.known
	CausticSpatter.Splash.known = CausticSpatter.known
	Flagellation.Buff.known = Flagellation.known
	Flagellation.Persist.known = Flagellation.known
	CoupDeGrace.Buff.known = CoupDeGrace.known

	self.combo_points.max_spend = 5 + (DeeperStratagem.known and 1 or 0) + (DeviousStratagem.known and 1 or 0) + (SecretStratagem.known and 1 or 0) + (SanguineStratagem.known and 1 or 0)

	Abilities:Update()
	self:UpdatePoisons()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, cooldown, start, ends, spellId, speed, max_speed, speed_mh, speed_oh
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.pool_energy = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.0
	cooldown = GetSpellCooldown(61304)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.energy.regen = GetPowerRegenForPowerType(3)
	self.energy.current = UnitPower('player', 3) + (self.energy.regen * self.execute_remains)
	self.energy.current = clamp(self.energy.current, 0, self.energy.max)
	self.energy.deficit = self.energy.max - self.energy.current
	self.energy.pct = (self.energy.current / self.energy.max) * 100
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	self:UpdateThreat()

	TrackedAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	if AdrenalineRush.known and AdrenalineRush:Up() then
		self.gcd = self.gcd - 0.2
	end
	for i = 1, 7 do
		self.combo_points.supercharged[i] = Supercharger.known and Supercharger[i]:Up()
	end
	self.combo_points.effective = self:ComboPoints()
	self.stealth_remains = max(ShadowDance.known and ShadowDance:Remains() or 0, (Subterfuge.known or UnderhandedUpperHand.known) and Subterfuge:Remains() or 0)
	self.stealthed_nomeld = self.stealth_remains > 0 or Stealth:Up() or Vanish:Up()
	self.stealthed = self.stealthed_nomeld or (Racial.Shadowmeld.known and Racial.Shadowmeld:Up())
	self.danse_stacks = DanseMacabre.known and DanseMacabre:Stack() or 0

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if not self.initialized then
		UI:ScanActionButtons()
		UI:ScanActionSlots()
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
		self.guid = UnitGUID('player')
		self.name = UnitName('player')
		self.initialized = true
	end
	assassinPreviousPanel.ability = nil
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 15
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			assassinPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			assassinPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = ToUID(guid) or 0
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		assassinPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Stunned()
	return CheapShot:Up() or KidneyShot:Up()
end

-- End Target Functions

-- Start Ability Modifications

function Ability:EnergyCost()
	if GoremawsBite.known and self.cp_cost > 0 and GoremawsBite.Buff:Up() then
		return 0
	end
	local cost = self.energy_cost
	if ShadowFocus.known and Player.stealthed then
		cost = cost - (cost * 0.15)
	end
	if TightSpender.known and self.cp_cost > 0 then
		cost = cost - (cost * 0.06)
	end
	return cost
end

function Ambush:Available()
	return (
		Player.stealthed or
		(Audacity.known and Audacity:Up()) or
		(Blindside.known and Blindside:Up())
	)
end

function Ambush:EnergyCost()
	if Blindside.known and Blindside:Up() then
		return 0
	end
	local cost = Ability.EnergyCost(self)
	if ViciousVenoms.known then
		cost = cost + (5 * ViciousVenoms.rank)
	end
	return cost
end

function Mutilate:EnergyCost()
	local cost = Ability.EnergyCost(self)
	if ViciousVenoms.known then
		cost = cost + (5 * ViciousVenoms.rank)
	end
	return cost
end

function Shadowstrike:Available()
	return Player.stealthed
end

function CheapShot:EnergyCost()
	if DirtyTricks.known then
		return 0
	end
	return Ability.EnergyCost(self)
end
Gouge.EnergyCost = CheapShot.EnergyCost

function CheapShot:Available()
	return Target.stunnable and Player.stealthed
end

function Gouge:Available()
	return Target.stunnable
end
KidneyShot.Available = Gouge.Available

function DanseMacabre:UsedFor(ability)
	return Player.danse_stacks >= 1 and ability.last_used >= self.last_gained
end

function BetweenTheEyes:Duration(comboPoints, appliedBy)
	return self.buff_duration + (3 * (comboPoints or Player.combo_points.current))
end

function BetweenTheEyes:Free()
	return Crackshot.known and Player.stealthed_nomeld
end

function Envenom:Duration(comboPoints, appliedBy)
	return (comboPoints or Player.combo_points.current)
end

function Rupture:Duration(comboPoints, appliedBy)
	return self.buff_duration + (4 * (comboPoints or Player.combo_points.current)) + (CorruptTheBlood.known and 3 or 0)
end

function CrimsonTempest:Duration(comboPoints, appliedBy)
	return self.buff_duration + (2 * (comboPoints or Player.combo_points.current))
end

function SliceAndDice:Duration(comboPoints, appliedBy)
	return self.buff_duration + (6 * (comboPoints or Player.combo_points.current))
end

function Opportunity:MaxStack()
	return 1 + (FanTheHammer.known and 5 or 0)
end

function Vanish:Available()
	return not Player.stealthed and (Player.group_size > 1 or Opt.vanish_solo)
end
Racial.Shadowmeld.Available = Vanish.Available

function Stealth:Available()
	return not (
		Player:TimeInCombat() > 0 or
		self:Up() or
		Vanish:Up() or
		(ShadowDance.known and ShadowDance:Up())
	)
end

function ShadowDance:Available()
	return not Player.stealthed
end

function Garrote:TickingPoisoned()
	local count, guid, aura, poisoned = 0
	for guid, aura in next, self.aura_targets do
		if aura.expires - Player.time > Player.execute_remains then
			poisoned = Poison.Deadly.DoT.aura_targets[guid] or Poison.Wound.DoT.aura_targets[guid] or Poison.Amplifying.DoT.aura_targets[guid]
			if poisoned then
				if poisoned.expires - Player.time > Player.execute_remains then
					count = count + 1
				end
			end
		end
	end
	return count
end
Rupture.TickingPoisoned = Garrote.TickingPoisoned

function Dispatch:EnergyCost()
	local cost = Ability.EnergyCost(self)
	if SummarilyDispatched.known then
		cost = cost - (SummarilyDispatched:Stack() * 5)
	end
	return cost
end

function PistolShot:EnergyCost()
	local cost = Ability.EnergyCost(self)
	if Opportunity:Up() then
		cost = cost * 0.50
	end
	return cost
end

function Shiv:EnergyCost()
	if TinyToxicBlade.known then
		return 0
	end
	return Ability.EnergyCost(self)
end

CountTheOdds.triggers = {
	[Ambush] = true,
	[CoupDeGrace] = true,
	[Dispatch] = true,
	[SinisterStrike] = true,
}

Supercharger.finishers = {
	[BetweenTheEyes] = true,
	[BlackPowder] = true,
	[CoupDeGrace] = true,
	[CrimsonTempest] = true,
	[Dispatch] = true,
	[Envenom] = true,
	[Eviscerate] = true,
	[Rupture] = true,
	[SecretTechnique] = true,
}

function Supercharger:Remains(...)
	local remains
	for i = 1, 7 do
		remains = self[i]:Remains(...)
		if remains > 0 then
			return remains
		end
	end
	return 0
end

Supercharger[1].Remains = function(self)
	if self.consumed then
		return 0 -- BUG: the buff remains for a second or so after it is consumed
	end
	return Ability.Remains(self)
end
for i = 1, 7 do
	Supercharger[i].Remains = Supercharger[1].Remains
end

RollTheBones.Broadside.Remains = function(self, rtbOnly)
	if rtbOnly and self.trigger ~= RollTheBones then
		return 0
	end
	return Ability.Remains(self)
end
RollTheBones.BuriedTreasure.Remains = RollTheBones.Broadside.Remains
RollTheBones.GrandMelee.Remains = RollTheBones.Broadside.Remains
RollTheBones.RuthlessPrecision.Remains = RollTheBones.Broadside.Remains
RollTheBones.SkullAndCrossbones.Remains = RollTheBones.Broadside.Remains
RollTheBones.TrueBearing.Remains = RollTheBones.Broadside.Remains

function RollTheBones:Stack(rtbOnly)
	local count, buff = 0
	for buff in next, self.Buffs do
		count = count + (buff:Up(rtbOnly) and 1 or 0)
	end
	return count
end

function RollTheBones:Remains(rtbOnly)
	local remains, max, buff = 0, 0
	for buff in next, self.Buffs do
		remains = buff:Remains(rtbObly)
		if remains > max then
			max = remains
		end
	end
	return max
end

function RollTheBones:WillLose(buff)
	local count = self:Stack()
	if not buff then
		return count
	end
	if buff:Down() then
		return false
	end
	return true
end

function ShadowTechniques:Energize(amount, overCap, powerType)
	if powerType ~= 4 then
		return
	end
	self.auto_count = 0
end

function ShadowTechniques:TimeTo(autoCount)
	if autoCount <= self.auto_count then
		return 0
	end
	if Player.swing.oh.speed > 0 then
		if autoCount - self.auto_count == 1 then
			return max(0, min(Player.swing.mh.remains, Player.swing.oh.remains) - Player.execute_remains)
		end
		return max(0, (autoCount - self.auto_count) * ((Player.swing.mh.speed + Player.swing.oh.speed) / 2 / 2) - min(Player.swing.mh.remains, Player.swing.oh.remains) - Player.execute_remains)
	end
	if autoCount - self.auto_count == 1 then
		return max(0, Player.swing.mh.remains - Player.execute_remains)
	end
	return max(0, (autoCount - self.auto_count) * Player.swing.mh.speed - Player.swing.mh.remains - Player.execute_remains)
end

function Poison.Instant:Default()
	local prio = (
		(self.lethal and Opt.poison_priority.lethal) or
		(self.nonlethal and Opt.poison_priority.nonlethal)
	)
	for i, spellId in next, prio do
		if spellId == self.spellId then
			table.remove(prio, i)
		end
	end
	table.insert(prio, 1, self.spellId)
	local prio = (
		(self.lethal and Player.poison.lethal) or
		(self.nonlethal and Player.poison.nonlethal)
	)
	for i, ability in next, prio do
		if ability == self then
			table.remove(prio, i)
		end
	end
	table.insert(prio, 1, self)
end

function Poison.Instant:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	self:Default()
end

for _, ability in next, Poison do
	ability.Default = Poison.Instant.Default
	ability.CastSuccess = Poison.Instant.CastSuccess
end

function Vanish:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Player.stealth_time = Player.time
end
Racial.Shadowmeld.CastSuccess = Vanish.CastSuccess

function FollowTheBlood:Remains()
	if Rupture:Ticking() >= 2 then
		return Rupture:HighestRemains()
	end
	return 0
end

function ImprovedGarrote:Remains(aura)
	local remains = Ability.Remains(self)
	if aura and remains < 600 then
		return 0
	end
	return max(remains, self.Fading:Remains())
end

function IndiscriminateCarnage:Remains(aura)
	local remains = Ability.Remains(self)
	if aura and remains < 600 then
		return 0
	end
	return max(remains, self.Fading:Remains())
end

function MasterAssassin:Remains(aura)
	local remains = Ability.Remains(self)
	if aura and remains < 600 then
		return 0
	end
	return max(remains, self.Fading:Remains())
end

function Subterfuge:Duration()
	return self.rank * self.buff_duration
end

function Rupture:NextMultiplier()
	local multiplier, aura = 1.00
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not aura then
			break
		elseif Finality.Rupture:Match(aura.spellId) then
			multiplier = multiplier * 1.25
		end
	end
	return multiplier
end

function Garrote:NextMultiplier()
	local multiplier, aura = 1.00
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not aura then
			break
		elseif ImprovedGarrote:Match(aura.spellId) or ImprovedGarrote.Fading:Match(aura.spellId) then
			multiplier = multiplier * 1.50
		end
	end
	return multiplier
end

function CoupDeGrace:Available()
	return self.Buff:Capped()
end

function Eviscerate:Available()
	return not CoupDeGrace:Available()
end
Dispatch.Available = Eviscerate.Available

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

local function Pool(ability, extra)
	Player.pool_energy = ability:EnergyCost() + (extra or 0)
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.ASSASSINATION].Main = function(self)
	if Player.health.pct < Opt.heal then
		if CrimsonVial:Usable() then
			UseExtra(CrimsonVial)
		end
	end
	if Player:TimeInCombat() == 0 then
		local apl = self:precombat()
		if apl then return apl end
	end
--[[
actions=stealth
actions+=/kick
actions+=/variable,name=single_target,value=spell_targets.fan_of_knives<2
actions+=/variable,name=regen_saturated,value=energy.regen_combined>30
actions+=/variable,name=in_cooldowns,value=dot.deathmark.ticking|dot.kingsbane.ticking|debuff.shiv.up
actions+=/variable,name=clip_envenom,value=buff.envenom.up&buff.envenom.remains.1<=1
actions+=/variable,name=upper_limit_energy,value=energy.pct>=(50-10*talent.vicious_venoms.rank)
actions+=/variable,name=avoid_tea,value=energy>40+50+5*talent.vicious_venoms.rank
actions+=/variable,name=cd_soon,value=cooldown.kingsbane.remains<3&!cooldown.kingsbane.ready
actions+=/variable,name=not_pooling,value=variable.in_cooldowns|!variable.cd_soon&variable.avoid_tea&buff.darkest_night.up|!variable.cd_soon&variable.avoid_tea&variable.clip_envenom|variable.upper_limit_energy|fight_remains<=20
actions+=/variable,name=scent_effective_max_stacks,value=(spell_targets.fan_of_knives*talent.scent_of_blood.rank*2)>?20
actions+=/variable,name=scent_saturation,value=buff.scent_of_blood.stack>=variable.scent_effective_max_stacks
actions+=/call_action_list,name=stealthed,if=stealthed.rogue|stealthed.improved_garrote|master_assassin_remains>0
actions+=/call_action_list,name=cds
actions+=/call_action_list,name=core_dot
actions+=/call_action_list,name=aoe_dot,if=!variable.single_target
actions+=/call_action_list,name=direct
actions+=/arcane_torrent,if=energy.deficit>=15+energy.regen_combined
actions+=/arcane_pulse
actions+=/lights_judgment
actions+=/bag_of_tricks
]]
	self.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(6, Player.enemies - 1)) or (Kingsbane.known and Kingsbane:Ticking() > 0) or (Deathmark.known and Deathmark:Ticking() > 0)
	self.single_target = Player.enemies < 2
	self.energy_regen_combined = Player.energy.regen + (Garrote:TickingPoisoned() + Rupture:TickingPoisoned()) * 8 / 2
	self.regen_saturated = self.energy_regen_combined > 30
	self.in_cooldowns = Deathmark:Ticking() > 0 or Kingsbane:Ticking() > 0 or Shiv:Up()
	self.clip_envenom = Envenom:Up() and Envenom:Remains() <= 1
	self.upper_limit_energy = Player.energy.pct >= (50 - (10 * ViciousVenoms.rank))
	self.avoid_tea = Player.energy.current > (40 + 50 + (5 * ViciousVenoms.rank))
	self.cd_soon = between(Kingsbane:Cooldown(), 0.1, 3)
	self.not_pooling = (
		self.in_cooldowns or
		self.upper_limit_energy or
		(Target.boss and Target.timeToDie <= 20) or
		(not self.cd_soon and self.avoid_tea and (self.clip_envenom or DarkestNight:Up()))
	)
	self.scent_effective_max_stacks = min(ScentOfBlood:MaxStack(), Player.enemies * ScentOfBlood.rank * 2)
	self.scent_saturation = ScentOfBlood:Stack() >= self.scent_effective_max_stacks
	local apl
	if Player.stealthed or (ImprovedGarrote.known and ImprovedGarrote:Up()) or (MasterAssassin.known and MasterAssassin:Up()) then
		apl = self:stealthed()
		if apl then return apl end
	end
	if self.use_cds then
		apl = self:cds()
		if apl then return apl end
	end
	if apl then return apl end
	apl = self:core_dot()
	if apl then return apl end
	if not self.single_target then
		apl = self:aoe_dot()
		if apl then return apl end
	end
	apl = self:direct()
	if apl then return apl end
end

APL[SPEC.ASSASSINATION].precombat_variables = function(self)
--[[
actions.precombat+=/variable,name=trinket_sync_slot,value=1,if=trinket.1.has_stat.any_dps&(!trinket.2.has_stat.any_dps|trinket.1.cooldown.duration>=trinket.2.cooldown.duration)&!trinket.2.is.treacherous_transmitter|trinket.1.is.treacherous_transmitter
actions.precombat+=/variable,name=trinket_sync_slot,value=2,if=trinket.2.has_stat.any_dps&(!trinket.1.has_stat.any_dps|trinket.2.cooldown.duration>trinket.1.cooldown.duration)&!trinket.1.is.treacherous_transmitter|trinket.2.is.treacherous_transmitter
actions.precombat+=/variable,name=effective_spend_cp,value=cp_max_spend-2<?5*talent.hand_of_fate
]]
	self.effective_spend_cp = max(HandOfFate.known and 5 or 0, Player.combo_points.max_spend - 2)
end

APL[SPEC.ASSASSINATION].precombat = function(self)
--[[
actions.precombat=apply_poison
actions.precombat+=/snapshot_stats
actions.precombat+=/stealth
actions.precombat+=/slice_and_dice,precombat_seconds=1
]]
	if Opt.poisons then
		if Player.poison.lethal[1] and Player.poison.lethal[1]:Usable() and Player.poison.lethal[1]:Remains() < 300 then
			return Player.poison.lethal[1]
		end
		if DragonTemperedBlades.known and Player.poison.lethal[2] and Player.poison.lethal[2]:Usable() and Player.poison.lethal[2]:Remains() < 300 then
			return Player.poison.lethal[2]
		end
		if Player.poison.nonlethal[1] and Player.poison.nonlethal[1]:Usable() and Player.poison.nonlethal[1]:Remains() < 300 then
			return Player.poison.nonlethal[1]
		end
		if DragonTemperedBlades.known and Player.poison.nonlethal[2] and Player.poison.nonlethal[2]:Usable() and Player.poison.nonlethal[2]:Remains() < 300 then
			return Player.poison.nonlethal[2]
		end
	end
	if Stealth:Usable() then
		return Stealth
	end
	if SliceAndDice:Usable() and SliceAndDice:Remains() < (4 * Player.combo_points.current) and Player.combo_points.current >= 2 and Target.timeToDie > SliceAndDice:Remains() then
		return SliceAndDice
	end
end

APL[SPEC.ASSASSINATION].aoe_dot = function(self)
--[[
actions.aoe_dot=variable,name=dot_finisher_condition,value=combo_points>=variable.effective_spend_cp&(pmultiplier<=1)
actions.aoe_dot+=/crimson_tempest,target_if=min:remains,if=spell_targets>=2&variable.dot_finisher_condition&refreshable&target.time_to_die-remains>6
actions.aoe_dot+=/garrote,cycle_targets=1,if=combo_points.deficit>=1&(pmultiplier<=1)&refreshable&!variable.regen_saturated&target.time_to_die-remains>12
actions.aoe_dot+=/rupture,cycle_targets=1,if=variable.dot_finisher_condition&refreshable&(!dot.kingsbane.ticking|buff.cold_blood.up)&(!variable.regen_saturated&(talent.scent_of_blood.rank=2|talent.scent_of_blood.rank<=1&(buff.indiscriminate_carnage.up|target.time_to_die-remains>15)))&target.time_to_die-remains>(7+(talent.dashing_scoundrel*5)+(variable.regen_saturated*6))&!buff.darkest_night.up
actions.aoe_dot+=/rupture,cycle_targets=1,if=variable.dot_finisher_condition&refreshable&(!dot.kingsbane.ticking|buff.cold_blood.up)&variable.regen_saturated&!variable.scent_saturation&target.time_to_die-remains>19&!buff.darkest_night.up
actions.aoe_dot+=/garrote,if=refreshable&combo_points.deficit>=1&(pmultiplier<=1|remains<=tick_time&spell_targets.fan_of_knives>=3)&(remains<=tick_time*2&spell_targets.fan_of_knives>=3)&(target.time_to_die-remains)>4&master_assassin_remains=0
]]
	self.dot_finisher_condition = Player.combo_points.current >= self.effective_spend_cp
	if CrimsonTempest:Usable() and Player.enemies >= 2 and self.dot_finisher_condition and CrimsonTempest:Refreshable() and (Target.timeToDie - CrimsonTempest:Remains()) > 6 then
		return CrimsonTempest
	end
	if Garrote:Usable() and Player.combo_points.deficit >= 1 and Garrote:Multiplier() <= 1 and Garrote:Refreshable() and not self.regen_saturated and (Target.timeToDie - Garrote:Remains()) > 12 then
		return Garrote
	end
	if Rupture:Usable() and self.dot_finisher_condition and Rupture:Refreshable() and not self.regen_saturated and DarkestNight:Down() and (Kingsbane:Ticking() == 0 or (ColdBlood.known and ColdBlood:Up())) and (
		(((ScentOfBlood.rank >= 2 or (IndiscriminateCarnage:Up() or (Target.timeToDie - Rupture:Remains()) > 15))) and (Target.timeToDie - Rupture:Remains()) > (7 + (DashingScoundrel.known and 5 or 0) + (self.regen_satured and 6 or 0))) or
		(not self.scent_saturation and (Target.timeToDie - Rupture:Remains()) > 19)
	) then
		return Rupture
	end
	if Garrote:Usable() and Player.combo_points.deficit >= 1 and Garrote:Refreshable() and (Garrote:Multiplier() <= 1 or (Garrote:Remains() <= Garrote:TickTime() and Player.enemies >= 3)) and (Target.timeToDie - Garrote:Remains()) > 4 and (not MasterAssassin.known or MasterAssassin:Down()) then
		return Garrote
	end
end

APL[SPEC.ASSASSINATION].cds = function(self)
--[[
actions.cds=variable,name=deathmark_ma_condition,value=!talent.master_assassin.enabled|dot.garrote.ticking
actions.cds+=/variable,name=deathmark_kingsbane_condition,value=!talent.kingsbane|cooldown.kingsbane.remains<=2
actions.cds+=/variable,name=deathmark_condition,value=!stealthed.rogue&buff.slice_and_dice.remains>5&dot.rupture.ticking&(buff.envenom.up|spell_targets.fan_of_knives>1)&!debuff.deathmark.up&variable.deathmark_ma_condition&variable.deathmark_kingsbane_condition
actions.cds+=/call_action_list,name=items
actions.cds+=/invoke_external_buff,name=power_infusion,if=dot.deathmark.ticking
actions.cds+=/deathmark,if=(variable.deathmark_condition&target.time_to_die>=10)|fight_remains<=20
actions.cds+=/call_action_list,name=shiv
actions.cds+=/kingsbane,if=(debuff.shiv.up|cooldown.shiv.remains<6)&(buff.envenom.up|spell_targets.fan_of_knives>1)&(cooldown.deathmark.remains>=50|dot.deathmark.ticking)|fight_remains<=15
actions.cds+=/thistle_tea,if=!buff.thistle_tea.up&dot.kingsbane.ticking&dot.kingsbane.remains<8|!buff.thistle_tea.up&cooldown.thistle_tea.charges>=2&debuff.shiv.remains>6|!buff.thistle_tea.up&fight_remains<=cooldown.thistle_tea.charges*6
actions.cds+=/call_action_list,name=misc_cds
actions.cds+=/call_action_list,name=vanish,if=!stealthed.all&master_assassin_remains=0
actions.cds+=/cold_blood,use_off_gcd=1,if=(buff.fatebound_coin_tails.stack>0&buff.fatebound_coin_heads.stack>0)|debuff.shiv.up&(cooldown.deathmark.remains>50|!talent.inevitabile_end&effective_combo_points>=variable.effective_spend_cp)
]]
	self:items()
	if Deathmark:Usable() and not Player.stealthed and Deathmark:Refreshable() and (
		(Target.timeToDie >= 10 and SliceAndDice:Remains() > 5 and Rupture:Up() and (Envenom:Up() or Player.enemies > 1) and (not MasterAssassin.known or Garrote:Up()) and (not Kingsbane.known or Kingsbane:Ready(2))) or
		(Target.boss and Target.timeToDie <= 20)
	) then
		UseCooldown(Deathmark)
	end
	local apl = self:shiv()
	if apl then return apl end
	if Kingsbane:Usable() and (
		((Shiv:Up() or Shiv:Ready(6)) and (Player.enemies > 1 or Envenom:Up()) and (Deathmark:Ticking() > 0 or not Deathmark:Ready(50))) or
		(Target.boss and Target.timeToDie <= 15)
	) then
		UseCooldown(Kingsbane)
	end
	if ThistleTea:Usable() and ThistleTea:Down() and (
		(Kingsbane:Ticking() > 0 and Kingsbane:HighestRemains() < 8) or
		(ThistleTea:Charges() >= 2 and Shiv:Remains() > 6) or
		(Target.boss and Target.timeToDie <= ThistleTea:ChargesFractional() * 6)
	) then
		UseCooldown(ThistleTea)
	end
	if not Player.stealthed and MasterAssassin:Down() then
		apl = self:vanish()
		if apl then return apl end
	end
	if ColdBlood:Usable() and (
		(Fatebound.known and FateboundCoinTails:Up() and FateboundCoinHeads:Up()) or
		(Shiv:Up() and (not Deathmark:Ready(50) or (InevitableEnds.known and Player.combo_points.effective >= self.effective_spend_cp)))
	) then
		UseCooldown(ColdBlood)
	end
end

APL[SPEC.ASSASSINATION].core_dot = function(self)
--[[
actions.core_dot=garrote,if=combo_points.deficit>=1&(pmultiplier<=1)&refreshable&target.time_to_die-remains>12
actions.core_dot+=/rupture,if=combo_points>=variable.effective_spend_cp&(pmultiplier<=1)&refreshable&target.time_to_die-remains>(4+(talent.dashing_scoundrel*5)+(variable.regen_saturated*6))&(!buff.darkest_night.up|talent.caustic_spatter&!debuff.caustic_spatter.up)
]]
	if Garrote:Usable() and Player.combo_points.deficit >= 1 and Garrote:Multiplier() <= 1 and Garrote:Refreshable() and (Target.timeToDie - Garrote:Remains()) > 12 then
		return Garrote
	end
	if Rupture:Usable() and Player.combo_points.current >= self.effective_spend_cp and Rupture:Refreshable() and (Target.timeToDie - Rupture:Remains()) > (4 + (DashingScoundrel.known and 5 or 0) + (self.regen_satured and 6 or 0)) and (DarkestNight:Down() or (CausticSpatter.known and CausticSpatter:Down())) then
		return Rupture
	end
end

APL[SPEC.ASSASSINATION].direct = function(self)
--[[
actions.direct=envenom,if=!buff.darkest_night.up&combo_points>=variable.effective_spend_cp&(variable.not_pooling|debuff.amplifying_poison.stack>=20|!variable.single_target)&!buff.vanish.up
actions.direct+=/envenom,if=buff.darkest_night.up&effective_combo_points>=cp_max_spend
actions.direct+=/variable,name=use_filler,value=combo_points<=variable.effective_spend_cp&!variable.cd_soon|variable.not_pooling|!variable.single_target
actions.direct+=/variable,name=use_caustic_filler,value=talent.caustic_spatter&dot.rupture.ticking&(!debuff.caustic_spatter.up|debuff.caustic_spatter.remains<=2)&combo_points.deficit>=1&!variable.single_target
actions.direct+=/mutilate,if=variable.use_caustic_filler
actions.direct+=/ambush,if=variable.use_caustic_filler
actions.direct+=/fan_of_knives,if=variable.use_filler&!priority_rotation&(spell_targets.fan_of_knives>=3-(talent.momentum_of_despair&talent.thrown_precision)|buff.clear_the_witnesses.up&!talent.vicious_venoms)
actions.direct+=/fan_of_knives,target_if=!dot.deadly_poison_dot.ticking&(!priority_rotation|dot.garrote.ticking|dot.rupture.ticking),if=variable.use_filler&spell_targets.fan_of_knives>=3-(talent.momentum_of_despair&talent.thrown_precision)
actions.direct+=/ambush,if=variable.use_filler&(buff.blindside.up|stealthed.rogue)&(!dot.kingsbane.ticking|debuff.deathmark.down|buff.blindside.up)
actions.direct+=/mutilate,target_if=!dot.deadly_poison_dot.ticking&!debuff.amplifying_poison.up,if=variable.use_filler&spell_targets.fan_of_knives=2
actions.direct+=/mutilate,if=variable.use_filler
]]
	if Envenom:Usable() and (
		(DarkestNight:Down() and Player.combo_points.current >= self.effective_spend_cp and (self.not_pooling or Poison.Amplifying.DoT:Stack() >= Poison.Amplifying.DoT:MaxStack() or not self.single_target) and Vanish:Down()) or
		(DarkestNight:Up() and Player.combo_points.effective >= Player.combo_points.max_spend)
	) then
		return Envenom
	end
	if CausticSpatter.known and Player.combo_points.deficit >= 1 and not self.single_target and Rupture:Up() and CausticSpatter:Remains() <= 2 then
		if Mutilate:Usable() then
			return Mutilate
		end
		if Ambush:Usable() then
			return Ambush
		end
	end
	if (
		(Player.combo_points.current <= self.effective_spend_cp and not self.cd_soon) or
		self.not_pooling or
		not self.single_target
	) then
		if not Opt.priority_rotation and FanOfKnives:Usable() and (
			(Player.enemies >= (3 - (MomentumOfDespair.known and ThrownPrecision.known and 1 or 0))) or
			(ClearTheWitnesses.known and not ViciousVenoms.known and ClearTheWitnesses:Up())
		) then
			return FanOfKnives
		end
		if Ambush:Usable() and (
			(Blindside.known and Blindside:Up()) or
			(Stealth:Up() and (Kingsbane:Ticking() == 0 or Deathmark:Down()))
		) then
			return Ambush
		end
		if Mutilate:Usable() then
			return Mutilate
		end
	end
end

APL[SPEC.ASSASSINATION].items = function(self)
--[[
actions.items=variable,name=base_trinket_condition,value=dot.rupture.ticking&cooldown.deathmark.remains<2|dot.deathmark.ticking|fight_remains<=22
actions.items+=/use_item,name=ashes_of_the_embersoul,use_off_gcd=1,if=(dot.kingsbane.ticking&dot.kingsbane.remains<=11)|fight_remains<=22
actions.items+=/use_item,name=algethar_puzzle_box,use_off_gcd=1,if=variable.base_trinket_condition
actions.items+=/use_item,name=treacherous_transmitter,use_off_gcd=1,if=variable.base_trinket_condition
actions.items+=/use_item,name=mad_queens_mandate,if=cooldown.deathmark.remains>=30&!dot.deathmark.ticking|fight_remains<=3
actions.items+=/do_treacherous_transmitter_task,use_off_gcd=1,if=dot.deathmark.ticking&variable.single_target|buff.realigning_nexus_convergence_divergence.up&buff.realigning_nexus_convergence_divergence.remains<=2|buff.cryptic_instructions.up&buff.cryptic_instructions.remains<=2|buff.errant_manaforge_emission.up&buff.errant_manaforge_emission.remains<=2|fight_remains<=15
actions.items+=/use_item,name=imperfect_ascendancy_serum,use_off_gcd=1,if=variable.base_trinket_condition
actions.items+=/use_items,slots=trinket1,if=(variable.trinket_sync_slot=1&(debuff.deathmark.up|fight_remains<=20)|(variable.trinket_sync_slot=2&(!trinket.2.cooldown.ready&dot.kingsbane.ticking|!debuff.deathmark.up&cooldown.deathmark.remains>20&dot.kingsbane.ticking))|!variable.trinket_sync_slot)
actions.items+=/use_items,slots=trinket2,if=(variable.trinket_sync_slot=2&(debuff.deathmark.up|fight_remains<=20)|(variable.trinket_sync_slot=1&(!trinket.1.cooldown.ready&dot.kingsbane.ticking|!debuff.deathmark.up&cooldown.deathmark.remains>20&dot.kingsbane.ticking))|!variable.trinket_sync_slot)
]]
	self.base_trinket_condition = Opt.trinket and (
		Deathmark:Ticking() > 0 or
		(Rupture:Ticking() > 0 and Deathmark:Ready(2)) or
		(Target.boss and Target.timeToDie <= 22)
	)
	if Trinket1:Usable() and self.base_trinket_condition then
		return UseCooldown(Trinket1)
	end
	if Trinket2:Usable() and self.base_trinket_condition then
		return UseCooldown(Trinket2)
	end
end

APL[SPEC.ASSASSINATION].shiv = function(self)
--[[
actions.shiv=variable,name=shiv_condition,value=!debuff.shiv.up&dot.garrote.ticking&dot.rupture.ticking
actions.shiv+=/variable,name=shiv_kingsbane_condition,value=talent.kingsbane&buff.envenom.up&variable.shiv_condition
actions.shiv+=/shiv,if=talent.arterial_precision&variable.shiv_condition&spell_targets.fan_of_knives>=4&dot.crimson_tempest.ticking
actions.shiv+=/shiv,if=!talent.lightweight_shiv.enabled&variable.shiv_kingsbane_condition&(dot.kingsbane.ticking&dot.kingsbane.remains<8|!dot.kingsbane.ticking&cooldown.kingsbane.remains>=20)&(!talent.crimson_tempest.enabled|variable.single_target|dot.crimson_tempest.ticking)
actions.shiv+=/shiv,if=talent.lightweight_shiv.enabled&variable.shiv_kingsbane_condition&(dot.kingsbane.ticking|cooldown.kingsbane.remains<=1)
actions.shiv+=/shiv,if=talent.arterial_precision&variable.shiv_condition&debuff.deathmark.up
actions.shiv+=/shiv,if=!talent.kingsbane&!talent.arterial_precision&variable.shiv_condition&(!talent.crimson_tempest.enabled|variable.single_target|dot.crimson_tempest.ticking)
actions.shiv+=/shiv,if=fight_remains<=cooldown.shiv.charges*8
]]
	if Shiv:Usable() and Shiv:Down() and Garrote:Ticking() > 0 and Rupture:Ticking() > 0 and Target.timeToDie > 3 and (
		(ArterialPrecision.known and (
			(Player.enemies >= 4 and CrimsonTempest:Ticking() > 0) or
			(Deathmark.known and Deathmark:Up())
		)) or
		(Kingsbane.known and Envenom:Up() and (
			(not LightweightShiv.known and ((Kingsbane:Ticking() > 0 and Kingsbane:HighestRemains() < 8) or (Kingsbane:Ticking() == 0 and not Kingsbane:Ready(20))) and (not CrimsonTempest.known or self.single_target or CrimsonTempest:Ticking() > 0)) or
			(LightweightShiv.known and (Kingsbane:Ticking() > 0 or Kingsbane:Ready(1)))
		)) or
		(not Kingsbane.known and not ArterialPrecision.known and (not CrimsonTempest.known or self.single_target or CrimsonTempest:Ticking() > 0)) or
		(Target.boss and Target.timeToDie <= (Shiv:ChargesFractional() * 8))
	) then
		return Shiv
	end
end

APL[SPEC.ASSASSINATION].stealthed = function(self)
--[[
actions.stealthed=pool_resource,for_next=1
actions.stealthed+=/ambush,if=!debuff.deathstalkers_mark.up&talent.deathstalkers_mark&combo_points<variable.effective_spend_cp&(dot.rupture.ticking|variable.single_target|!talent.subterfuge)
actions.stealthed+=/shiv,if=talent.kingsbane&dot.kingsbane.ticking&dot.kingsbane.remains<8&(!debuff.shiv.up&debuff.shiv.remains<1)&buff.envenom.up
actions.stealthed+=/envenom,if=effective_combo_points>=variable.effective_spend_cp&(dot.kingsbane.ticking&buff.envenom.remains<=3|buff.master_assassin_aura.up&variable.single_target)&(buff.cold_blood.up|buff.darkest_night.down&debuff.deathstalkers_mark.up|buff.darkest_night.up&effective_combo_points>=cp_max_spend)
actions.stealthed+=/rupture,target_if=effective_combo_points>=variable.effective_spend_cp&buff.indiscriminate_carnage.up&refreshable&(!variable.regen_saturated|!variable.scent_saturation|!dot.rupture.ticking)&target.time_to_die>15
actions.stealthed+=/garrote,target_if=min:remains,if=stealthed.improved_garrote&(remains<12|pmultiplier<=1|(buff.indiscriminate_carnage.up&active_dot.garrote<spell_targets.fan_of_knives))&!variable.single_target&target.time_to_die-remains>2&combo_points.deficit>2-buff.darkest_night.up*2
actions.stealthed+=/garrote,if=stealthed.improved_garrote&(pmultiplier<=1|refreshable)&combo_points.deficit>=1+2*talent.shrouded_suffocation
]]
	if DeathstalkersMark.known and Ambush:Usable(0, true) and DeathstalkersMark:Down() and Player.combo_points.current < self.effective_spend_cp and (Rupture:Ticking() > 0 or self.single_target or not Subterfuge.known) then
		return Pool(Ambush)
	end
	if Kingsbane.known and Shiv:Usable() and Kingsbane:Ticking() > 0 and Kingsbane:HighestRemains() < 8 and Shiv:Remains() < 1 and Envenom:Up() then
		return Shiv
	end
	if Envenom:Usable() and Player.combo_points.effective >= self.effective_spend_cp and (
		(Kingsbane:Ticking() > 0 and Envenom:Remains() <= 3) or
		(MasterAssassin:Up(true) and self.single_target)
	) and (
		(ColdBlood.known and ColdBlood:Up()) or
		(DeathstalkersMark.known and (
			(DarkestNight:Down() and DeathstalkersMark:Up()) or
			(DarkestNight:Up() and Player.combo_points.effective >= Player.combo_points.max_spend)
		))
	) then
		return Envenom
	end
	if Rupture:Usable() and Player.combo_points.effective >= self.effective_spend_cp and Rupture:Refreshable() and IndiscriminateCarnage:Up() and (not self.regen_saturated or not self.scent_saturation or Rupture:Ticking() == 0) and Target.timeToDie > 15 then
		return Rupture
	end
	if Garrote:Usable() and ImprovedGarrote:Up() and (
		((Garrote:Remains() < 12 or Garrote:Multiplier() <= 1 or (IndiscriminateCarnage:Up() and Garrote:Ticking() < Player.enemies)) and not self.single_target and (Target.timeToDie - Garrote:Remains()) > 2 and Player.combo_points.deficit > (2 - (DarkestNight:Up() and 2 or 0))) or
		((Garrote:Multiplier() <= 1 or Garrote:Refreshable()) and Player.combo_points.deficit >= (1 + (ShroudedSuffocation.known and 2 or 0)))
	) then
		return Garrote
	end
end

APL[SPEC.ASSASSINATION].vanish = function(self)
--[[
actions.vanish=pool_resource,for_next=1,extra_amount=45
actions.vanish+=/vanish,if=!buff.fatebound_lucky_coin.up&effective_combo_points>=variable.effective_spend_cp&(buff.fatebound_coin_tails.stack>=5|buff.fatebound_coin_heads.stack>=5)
actions.vanish+=/vanish,if=!talent.master_assassin&!talent.indiscriminate_carnage&talent.improved_garrote&cooldown.garrote.up&(dot.garrote.pmultiplier<=1|dot.garrote.refreshable)&(debuff.deathmark.up|cooldown.deathmark.remains<4)&combo_points.deficit>=(spell_targets.fan_of_knives>?4)
actions.vanish+=/pool_resource,for_next=1,extra_amount=45
actions.vanish+=/vanish,if=talent.indiscriminate_carnage&talent.improved_garrote&cooldown.garrote.up&(dot.garrote.pmultiplier<=1|dot.garrote.refreshable)&spell_targets.fan_of_knives>2&(target.time_to_die-remains>15|raid_event.adds.in>20)
actions.vanish+=/vanish,if=talent.master_assassin&debuff.deathmark.up&dot.kingsbane.remains<=6+3*talent.subterfuge.rank
actions.vanish+=/vanish,if=talent.improved_garrote&cooldown.garrote.up&(dot.garrote.pmultiplier<=1|dot.garrote.refreshable)&(debuff.deathmark.up|cooldown.deathmark.remains<4)&raid_event.adds.in>30
]]
	if not Vanish:Usable() then
		return
	end
	if LuckyCoin.known and LuckyCoin:Down() and Player.combo_points.effective >= self.effective_spend_cp and (FateboundCoin.Tails:Stack() >= 5 or FateboundCoin.Heads:Stack() >= 5) then
		return UseCooldown(Pool(Vanish, 45))
	end
	if not MasterAssassin.known and not IndiscriminateCarnage.known and ImprovedGarrote.known and Garrote:Ready() and (Garrote:Multiplier() <= 1 or Garrote:Refreshable()) and (Deathmark:Up() or Deathmark:Ready(4)) and Player.combo_points.deficit >= min(4, Player.enemies) then
		return UseCooldown(Vanish)
	end
	if IndiscriminateCarnage.known and ImprovedGarrote.known and Garrote:Ready() and (Garrote:Multiplier() <= 1 or Garrote:Refreshable()) and Player.enemies > 2 then
		return UseCooldown(Pool(Vanish, 45))
	end
	if Deathmark.known and (
		(MasterAssassin.known and Deathmark:Up() and Kingsbane:HighestRemains() <= (6 + Subterfuge:Duration())) or
		(ImprovedGarrote.known and Garrote:Ready() and (Garrote:Multiplier() <= 1 or Garrote:Refreshable()) and (Deathmark:Up() or Deathmark:Ready(4)))
	) then
		return UseCooldown(Vanish)
	end
end

APL[SPEC.OUTLAW].Main = function(self)
	self.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or AdrenalineRush:Up())
	self:rtb()

	if Player.health.pct < Opt.heal then
		if CrimsonVial:Usable() then
			UseExtra(CrimsonVial)
		end
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=apply_poison
actions.precombat+=/flask
actions.precombat+=/augmentation
actions.precombat+=/food
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/blade_flurry,precombat_seconds=3,if=talent.underhanded_upper_hand
actions.precombat+=/roll_the_bones,precombat_seconds=2
actions.precombat+=/adrenaline_rush,precombat_seconds=1,if=talent.improved_adrenaline_rush
actions.precombat+=/slice_and_dice,precombat_seconds=1
actions.precombat+=/stealth
]]
		if Opt.poisons then
			if Player.poison.lethal[1] and Player.poison.lethal[1]:Usable() and Player.poison.lethal[1]:Remains() < 300 then
				return Player.poison.lethal[1]
			end
			if Player.poison.nonlethal[1] and Player.poison.nonlethal[1]:Usable() and Player.poison.nonlethal[1]:Remains() < 300 then
				return Player.poison.nonlethal[1]
			end
		end
		if self.use_cds and UnderhandedUpperHand.known and BladeFlurry:Usable() and AdrenalineRush:Ready() and BladeFlurry:Down() then
			UseCooldown(BladeFlurry)
		end
		if RollTheBones:Usable() and (self.rtb_reroll or self.rtb_remains < 5) then
			UseCooldown(RollTheBones)
		end
		if self.use_cds and ImprovedAdrenalineRush.known and AdrenalineRush:Usable() and AdrenalineRush:Down() then
			UseCooldown(AdrenalineRush)
		end
		if SliceAndDice:Usable() and SliceAndDice:Remains() < (4 * Player.combo_points.current) and Player.combo_points.current >= 2 and Target.timeToDie > SliceAndDice:Remains() then
			return SliceAndDice
		end
		if Stealth:Usable() then
			return Stealth
		end
	else
		if Racial.Shadowmeld.known and Stealth:Usable() and Racial.Shadowmeld:Up() then
			return Stealth
		end
	end
--[[
# Restealth if possible (no vulnerable enemies in combat)
actions=stealth
# Interrupt on cooldown to allow simming interactions with that
actions+=/kick
actions+=/variable,name=ambush_condition,value=(talent.hidden_opportunity|combo_points.deficit>=2+talent.improved_ambush+buff.broadside.up)&energy>=50
# Use finishers if at -1 from max combo points, or -2 in Stealth with Crackshot
actions+=/variable,name=finish_condition,value=effective_combo_points>=cp_max_spend-1-(stealthed.all&talent.crackshot)
# With multiple targets, this variable is checked to decide whether some CDs should be synced with Blade Flurry
actions+=/variable,name=blade_flurry_sync,value=spell_targets.blade_flurry<2&raid_event.adds.in>20|buff.blade_flurry.remains>gcd
actions+=/call_action_list,name=cds
# High priority stealth list, will fall through if no conditions are met
actions+=/call_action_list,name=stealth,if=stealthed.all
actions+=/run_action_list,name=finish,if=variable.finish_condition
actions+=/call_action_list,name=build
actions+=/arcane_torrent,if=energy.base_deficit>=15+energy.regen
actions+=/arcane_pulse
actions+=/lights_judgment
actions+=/bag_of_tricks
]]
	self.vanish_condition = Vanish.known and (Opt.vanish_solo or Player.group_size > 1)
	self.ambush_condition = Player.energy.current >= 50 and (HiddenOpportunity.known or Player.combo_points.deficit >= (2 + (ImprovedAmbush.known and 1 or 0) + (RollTheBones.Broadside:Up() and 1 or 0)))
	self.finish_condition = Player.combo_points.effective >= (Player.combo_points.max_spend - 1 - ((Player.stealthed and Crackshot.known) and 1 or 0))
	self.blade_flurry_sync = Player.enemies < 2 or BladeFlurry:Remains() > Player.gcd

	self:cds()
	if Player.stealthed then
		local apl = self:stealth()
		if apl then return apl end
	end
	if self.finish_condition then
		return self:finish()
	end
	return self:build()
end

APL[SPEC.OUTLAW].rtb = function(self)
--[[
# Custom value reroll
actions+=/variable,name=rtb_value,value=(buff.broadside.up*10)+(buff.true_bearing.up*11)+(buff.ruthless_precision.up*9)+(buff.skull_and_crossbones.up*8)+(buff.buried_treasure.up*4)+(buff.grand_melee.up*(3+((spell_targets.blade_flurry>1)*2)))
actions+=/variable,name=rtb_reroll,value=variable.rtb_value<(16+(7*buff.loaded_dice.up))
# Default Roll the Bones reroll rule: reroll for any buffs that aren't Buried Treasure, excluding Grand Melee in single target
actions+=/variable,name=rtb_reroll,value=rtb_buffs.will_lose=(rtb_buffs.will_lose.buried_treasure+rtb_buffs.will_lose.grand_melee&spell_targets.blade_flurry<2&raid_event.adds.in>10)
# Crackshot builds should reroll for True Bearing (or Broadside without Hidden Opportunity) if we won't lose over 1 buff
actions+=/variable,name=rtb_reroll,if=talent.crackshot,value=(!rtb_buffs.will_lose.true_bearing&talent.hidden_opportunity|!rtb_buffs.will_lose.broadside&!talent.hidden_opportunity)&rtb_buffs.will_lose<=1
# Hidden Opportunity builds without Crackshot should reroll for Skull and Crossbones or any 2 buffs excluding Grand Melee in single target
actions+=/variable,name=rtb_reroll,if=!talent.crackshot&talent.hidden_opportunity,value=!rtb_buffs.will_lose.skull_and_crossbones&(rtb_buffs.will_lose<2+rtb_buffs.will_lose.grand_melee&spell_targets.blade_flurry<2&raid_event.adds.in>10)
# Additional reroll rules if all active buffs will not be rolled away and we don't already have 5+ buffs outside of stealth
actions+=/variable,name=rtb_reroll,value=variable.rtb_reroll&rtb_buffs.longer=0|rtb_buffs.normal=0&rtb_buffs.longer>=1&rtb_buffs<5&rtb_buffs.max_remains<=39&!stealthed.all
# Avoid rerolls when we will not have time remaining on the fight or add wave to recoup the opportunity cost of the global
actions+=/variable,name=rtb_reroll,op=reset,if=!(raid_event.adds.remains>12|raid_event.adds.up&(raid_event.adds.in-raid_event.adds.remains)<6|target.time_to_die>12)|fight_remains<12
]]
	self.rtb_remains = RollTheBones:Remains(true)
	self.rtb_buffs = RollTheBones:Stack()
	self.rtb_will_lose = RollTheBones:WillLose()
	if Target.boss and Target.timeToDie < 12 then
		self.rtb_reroll = false
	elseif Opt.rtb_values.enabled then
		self.rtb_value = (
			(RollTheBones.Broadside:Up() and Opt.rtb_values.broadside or 0) +
			(RollTheBones.TrueBearing:Up() and Opt.rtb_values.true_bearing or 0) +
			(RollTheBones.RuthlessPrecision:Up() and Opt.rtb_values.ruthless_precision or 0) +
			(RollTheBones.SkullAndCrossbones:Up() and Opt.rtb_values.skull_and_crossbones or 0) +
			(RollTheBones.BuriedTreasure:Up() and Opt.rtb_values.buried_treasure or 0) +
			(RollTheBones.GrandMelee:Up() and (
				Opt.rtb_values.grand_melee + (Player.enemies > 1 and Opt.rtb_values.grand_melee_aoe or 0)
			) or 0)
		)
		self.rtb_reroll = self.rtb_value < (Opt.rtb_values.threshold + (LoadedDice:Up() and Opt.rtb_values.loaded_dice or 0))
	elseif Crackshot.known then
		self.rtb_reroll = self.rtb_will_lose <= 1 and ((HiddenOpportunity.known and not RollTheBones:WillLose(RollTheBones.TrueBearing)) or (not HiddenOpportunity.known and not RollTheBones:WillLose(RollTheBones.Broadside)))
	elseif HiddenOpportunity.known then
		self.rtb_reroll = not RollTheBones:WillLose(RollTheBones.SkullAndCrossbones) and self.rtb_will_lose < (2 + ((Player.enemies < 2 and RollTheBones:WillLose(RollTheBones.GrandMelee)) and 1 or 0))
	else
		self.rtb_reroll = self.rtb_will_lose == ((RollTheBones:WillLose(RollTheBones.BuriedTreasure) and 1 or 0) + ((Player.enemies < 2 and RollTheBones:WillLose(RollTheBones.GrandMelee)) and 1 or 0))
	end
end

APL[SPEC.OUTLAW].stealth = function(self)
--[[
# Stealth
actions.stealth=blade_flurry,if=talent.subterfuge&talent.hidden_opportunity&spell_targets>=2&buff.blade_flurry.remains<gcd
actions.stealth+=/cold_blood,if=variable.finish_condition
# High priority Between the Eyes for Crackshot, except not directly out of Shadowmeld
actions.stealth+=/between_the_eyes,if=variable.finish_condition&talent.crackshot&(!buff.shadowmeld.up|stealthed.rogue)
actions.stealth+=/dispatch,if=variable.finish_condition
# 2 Fan the Hammer Crackshot builds can consume Opportunity in stealth with max stacks, Broadside, and low CPs, or with Greenskins active
actions.stealth+=/pistol_shot,if=talent.crackshot&talent.fan_the_hammer.rank>=2&buff.opportunity.stack>=6&(buff.broadside.up&combo_points<=1|buff.greenskins_wickers.up)
actions.stealth+=/ambush,if=talent.hidden_opportunity
]]
	if Subterfuge.known and HiddenOpportunity.known and BladeFlurry:Usable() and Player.enemies >= 2 and BladeFlurry:Remains() < Player.gcd then
		UseCooldown(BladeFlurry)
	end
	if self.finish_condition then
		if ColdBlood:Usable() then
			UseCooldown(ColdBlood)
		end
		if Crackshot.known and BetweenTheEyes:Usable(0, true) and Racial.Shadowmeld:Down() then
			return Pool(BetweenTheEyes)
		end
		if Dispatch:Usable() then
			return Dispatch
		end
	end
	if Crackshot.known and PistolShot:Usable() and FanTheHammer.rank >= 2 and Opportunity:Stack() >= 6 and ((RollTheBones.Broadside:Up() and Player.combo_points.current <= 1) or GreenskinsWickers:Up()) then
		return PistolShot
	end
	if HiddenOpportunity.known and Ambush:Usable() then
		return Ambush
	end
end

APL[SPEC.OUTLAW].stealth_cds = function(self)
--[[
# Stealth Cooldowns
actions.stealth_cds=variable,name=vanish_opportunity_condition,value=!talent.shadow_dance&talent.fan_the_hammer.rank+talent.quick_draw+talent.audacity<talent.count_the_odds+talent.keep_it_rolling
# Hidden Opportunity builds without Crackshot use Vanish if Audacity is not active and when under max Opportunity stacks
actions.stealth_cds+=/vanish,if=talent.hidden_opportunity&!talent.crackshot&!buff.audacity.up&(variable.vanish_opportunity_condition|buff.opportunity.stack<buff.opportunity.max_stack)&variable.ambush_condition
# Crackshot builds or builds without Hidden Opportunity use Vanish at finish condition
actions.stealth_cds+=/vanish,if=(!talent.hidden_opportunity|talent.crackshot)&variable.finish_condition
# Crackshot builds use Dance at finish condition
actions.stealth_cds+=/shadow_dance,if=talent.crackshot&variable.finish_condition
# Hidden Opportunity builds without Crackshot use Dance if Audacity and Opportunity are not active
actions.stealth_cds+=/variable,name=shadow_dance_condition,value=buff.between_the_eyes.up&(!talent.hidden_opportunity|!buff.audacity.up&(talent.fan_the_hammer.rank<2|!buff.opportunity.up))&!talent.crackshot
actions.stealth_cds+=/shadow_dance,if=!talent.keep_it_rolling&variable.shadow_dance_condition&buff.slice_and_dice.up&(variable.finish_condition|talent.hidden_opportunity)&(!talent.hidden_opportunity|!cooldown.vanish.ready)
# Keep it Rolling builds without Crackshot use Dance at finish condition but hold it for an upcoming Keep it Rolling
actions.stealth_cds+=/shadow_dance,if=talent.keep_it_rolling&variable.shadow_dance_condition&(cooldown.keep_it_rolling.remains<=30|cooldown.keep_it_rolling.remains>120&(variable.finish_condition|talent.hidden_opportunity))
actions.stealth_cds+=/shadowmeld,if=variable.finish_condition&!cooldown.vanish.ready&!cooldown.shadow_dance.ready
]]
	self.vanish_opportunity_condition = not ShadowDance.known and (FanTheHammer.rank + (QuickDraw.known and 1 or 0) + (Audacity.known and 1 or 0)) < ((CountTheOdds.known and 1 or 0) + (KeepItRolling.known and 1 or 0))
	if self.vanish_condition and Vanish:Usable() and (
		(HiddenOpportunity.known and not Crackshot.known and Audacity:Down() and (self.vanish_opportunity_condition or Opportunity:Stack() < Opportunity:MaxStack()) and self.ambush_condition) or
		((not HiddenOpportunity.known or Crackshot.known) and self.finish_condition)
	) then
		return UseCooldown(Vanish)
	end
	if Crackshot.known and ShadowDance:Usable() and self.finish_condition then
		return UseCooldown(ShadowDance)
	end
	self.shadow_dance_condition = ShadowDance.known and not Crackshot.known and BetweenTheEyes:Up() and (not HiddenOpportunity.known or (Audacity:Down() and (FanTheHammer.rank < 2 or Opportunity:Down())))
	if ShadowDance:Usable() and self.shadow_dance_condition and (
		(not KeepItRolling.known and SliceAndDice:Up() and (self.finish_condition or HiddenOpportunity.known) and (not HiddenOpportunity.known or not self.vanish_condition or not Vanish:Ready())) or
		(KeepItRolling.known and (KeepItRolling:Ready(30) or (not KeepItRolling:Ready(120) and (self.finish_condition or HiddenOpportunity.known))))
	) then
		return UseCooldown(ShadowDance)
	end
	if self.vanish_condition and Racial.Shadowmeld:Usable() and self.finish_condition and not Vanish:Ready() and not ShadowDance:Ready() then
		return UseCooldown(Racial.Shadowmeld)
	end
end

APL[SPEC.OUTLAW].cds = function(self)
--[[
# Cooldowns  Use Adrenaline Rush if it is not active and at 2cp if Improved, but Crackshot builds can refresh it in stealth
actions.cds=adrenaline_rush,if=(!buff.adrenaline_rush.up|stealthed.all&talent.crackshot&talent.improved_adrenaline_rush)&(combo_points<=2|!talent.improved_adrenaline_rush)
# Maintain Blade Flurry on 2+ targets, and on single target with Underhanded
actions.cds+=/blade_flurry,if=(spell_targets>=2-talent.underhanded_upper_hand&!stealthed.rogue)&buff.blade_flurry.remains<gcd
# With Deft Maneuvers, use Blade Flurry on cooldown at 5+ targets, or at 3-4 targets if missing combo points equal to the amount given
actions.cds+=/blade_flurry,if=talent.deft_maneuvers&!variable.finish_condition&(spell_targets>=3&combo_points.deficit=spell_targets+buff.broadside.up|spell_targets>=5)
# Use Roll the Bones if reroll conditions are met, or with no buffs, or 7s before buffs expire with Vanish/Dance ready
actions.cds+=/roll_the_bones,if=rtb_buffs=0|(!talent.crackshot|buff.subterfuge.down&buff.shadow_dance.down)&(variable.rtb_reroll|rtb_buffs.max_remains<=7&(cooldown.shadow_dance.ready|cooldown.vanish.ready))
# Use Keep it Rolling with at least 3 buffs
actions.cds+=/keep_it_rolling,if=!variable.rtb_reroll&rtb_buffs>=3&(buff.shadow_dance.down|rtb_buffs>=6)
actions.cds+=/ghostly_strike
# Crackshot builds use stealth cooldowns if Between the Eyes is ready
actions.cds+=/call_action_list,name=stealth_cds,if=!stealthed.all&(!talent.crackshot|cooldown.between_the_eyes.ready)
actions.cds+=/thistle_tea,if=!buff.thistle_tea.up&(energy.base_deficit>=100|fight_remains<charges*6)
# Use Blade Rush at minimal energy outside of stealth
actions.cds+=/blade_rush,if=energy.base_time_to_max>4&!stealthed.all
actions.cds+=/potion,if=buff.bloodlust.react|fight_remains<30|buff.adrenaline_rush.up
actions.cds+=/blood_fury
actions.cds+=/berserking
actions.cds+=/fireblood
actions.cds+=/ancestral_call
# Default conditions for usable items.
actions.cds+=/use_items,slots=trinket1,if=buff.between_the_eyes.up|trinket.1.has_stat.any_dps|fight_remains<=20
actions.cds+=/use_items,slots=trinket2,if=buff.between_the_eyes.up|trinket.2.has_stat.any_dps|fight_remains<=20
]]
	if self.use_cds and AdrenalineRush:Usable() and (AdrenalineRush:Down() or (Player.stealthed and Crackshot.known and ImprovedAdrenalineRush.known)) and (Player.combo_points.current <= 2 or not ImprovedAdrenalineRush.known) then
		return UseCooldown(AdrenalineRush)
	end
	if BladeFlurry:Usable() and (
		(Player.enemies >= (2 - (UnderhandedUpperHand.known and 1 or 0)) and not Player.stealthed and BladeFlurry:Remains() < Player.gcd) or
		(DeftManeuvers.known and not self.finish_condition and (Player.enemies >= 5 or (Player.enemies >= 3 and Player.combo_points.deficit == (Player.enemies + (RollTheBones.Broadside:Up() and 1 or 0)))))
	) then
		return UseCooldown(BladeFlurry)
	end
	if RollTheBones:Usable() and (
		self.rtb_buffs == 0 or
		((not Crackshot.known or Player.stealth_remains <= 0) and (
			self.rtb_reroll or
			(self.rtb_remains <= 7 and (ShadowDance:Ready() or (self.vanish_condition and Vanish:Ready())))
		))
	) then
		return UseCooldown(RollTheBones)
	end
	if self.use_cds and KeepItRolling:Usable() and not self.rtb_reroll and self.rtb_buffs >= 3 and (ShadowDance:Down() or self.rtb_buffs >= 6) then
		return UseCooldown(KeepItRolling)
	end
	if self.use_cds and GhostlyStrike:Usable() and Stealth:Down() and Racial.Shadowmeld:Down() then
		return UseCooldown(GhostlyStrike)
	end
	if self.use_cds and not Player.stealthed and (not Crackshot.known or BetweenTheEyes:Ready()) then
		self:stealth_cds()
	end
	if ThistleTea:Usable() and ThistleTea:Down() and (
		Player.energy.deficit >= 100 or
		(Target.boss and Target.timeToDie < (ThistleTea:Charges() * 6))
	) then
		return UseCooldown(ThistleTea)
	end
	if self.use_cds and BladeRush:Usable() and not Player.stealthed and Player:EnergyTimeToMax() > 4 then
		return UseCooldown(BladeRush)
	end
	if Opt.trinket then
		if (Target.boss and Target.timeToDie < 20) or (BetweenTheEyes:Up() and (not GhostlyStrike.known or GhostlyStrike:Up())) then
			if Trinket1:Usable() then
				return UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				return UseCooldown(Trinket2)
			end
		end
	end
end

APL[SPEC.OUTLAW].finish = function(self)
--[[
# Finishers  Use Between the Eyes to keep the crit buff up, but on cooldown if Improved/Greenskins, and avoid overriding Greenskins
actions.finish=between_the_eyes,if=!talent.crackshot&(buff.between_the_eyes.remains<4|talent.improved_between_the_eyes|talent.greenskins_wickers)&!buff.greenskins_wickers.up
# Crackshot builds use Between the Eyes outside of Stealth if Vanish or Dance will not come off cooldown within the next cast
actions.finish+=/between_the_eyes,if=talent.crackshot&(cooldown.vanish.remains>45&cooldown.shadow_dance.remains>12)
actions.finish+=/slice_and_dice,if=buff.slice_and_dice.remains<fight_remains&refreshable
actions.finish+=/killing_spree,if=debuff.ghostly_strike.up|!talent.ghostly_strike
actions.finish+=/cold_blood
actions.finish+=/dispatch
]]
	if BetweenTheEyes:Usable(Player:EnergyTimeToMax(50), true) and (
		(not Crackshot.known and (not GreenskinsWickers.known or GreenskinsWickers:Down()) and (BetweenTheEyes:Remains() < 4 or ImprovedBetweenTheEyes.known or GreenskinsWickers.known)) or
		(Crackshot.known and ((not self.vanish_condition or not Vanish:Ready(45)) and not ShadowDance:Ready(12)) and (Player.enemies > 1 or Target.timeToDie > 12 or Target.boss))
	) then
		return Pool(BetweenTheEyes)
	end
	if SliceAndDice:Usable(0, true) and SliceAndDice:Refreshable() and (Player.enemies > 1 or SliceAndDice:Remains() < Target.timeToDie) and (not Player.combo_points.supercharged[Player.combo_points.current] or SliceAndDice:Down()) and (not SwiftSlasher.known or Player.combo_points.current >= Player.combo_points.max_spend) then
		return Pool(SliceAndDice)
	end
	if KillingSpree:Usable() and (not GhostlyStrike.known or GhostlyStrike:Up()) then
		UseCooldown(KillingSpree)
	end
	if ColdBlood:Usable() then
		UseCooldown(ColdBlood)
	end
	if Dispatch:Usable(0, true) then
		return Pool(Dispatch)
	end
end

APL[SPEC.OUTLAW].build = function(self)
--[[
# Builders
actions.build=echoing_reprimand
# High priority Ambush for Hidden Opportunity builds
actions.build+=/ambush,if=talent.hidden_opportunity&buff.audacity.up
# With Audacity + Hidden Opportunity + Fan the Hammer, consume Opportunity to proc Audacity any time Ambush is not available
actions.build+=/pistol_shot,if=talent.fan_the_hammer&talent.audacity&talent.hidden_opportunity&buff.opportunity.up&!buff.audacity.up
# Use Greenskins Wickers buff immediately with Opportunity unless running Fan the Hammer
actions.build+=/pistol_shot,if=buff.greenskins_wickers.up&(!talent.fan_the_hammer&buff.opportunity.up|buff.greenskins_wickers.remains<1.5)
# With Fan the Hammer, consume Opportunity at max stacks or if it will expire
actions.build+=/pistol_shot,if=talent.fan_the_hammer&buff.opportunity.up&(buff.opportunity.stack>=buff.opportunity.max_stack|buff.opportunity.remains<2)
# With Fan the Hammer, consume Opportunity based on CP deficit, and 2 Fan the Hammer Crackshot builds can briefly hold stacks for an upcoming stealth cooldown
actions.build+=/pistol_shot,if=talent.fan_the_hammer&buff.opportunity.up&combo_points.deficit>((1+talent.quick_draw)*talent.fan_the_hammer.rank)&(!cooldown.vanish.ready&!cooldown.shadow_dance.ready|stealthed.all|!talent.crackshot|talent.fan_the_hammer.rank<=1)
# If not using Fan the Hammer, then consume Opportunity based on energy, when it will exactly cap CPs, or when using Quick Draw
actions.build+=/pistol_shot,if=!talent.fan_the_hammer&buff.opportunity.up&(energy.base_deficit>energy.regen*1.5|combo_points.deficit<=1+buff.broadside.up|talent.quick_draw.enabled|talent.audacity.enabled&!buff.audacity.up)
# Fallback pooling just so Sinister Strike is never casted if Ambush is available for Hidden Opportunity builds
actions.build+=/pool_resource,for_next=1
actions.build+=/ambush,if=talent.hidden_opportunity
actions.build+=/sinister_strike
]]
	if HiddenOpportunity.known and Ambush:Usable() and Audacity:Up() then
		return Ambush
	end
	if PistolShot:Usable() and (
		(GreenskinsWickers.known and GreenskinsWickers:Up() and ((not FanTheHammer.known and Opportunity:Up()) or GreenskinsWickers:Remains() < 1.5)) or
		(Opportunity:Up() and (
			(FanTheHammer.known and (
				(Audacity.known and HiddenOpportunity.known and Audacity:Down()) or
				(Opportunity:Stack() >= Opportunity:MaxStack() or Opportunity:Remains() < 2) or
				(Player.combo_points.deficit > ((1 + (QuickDraw.known and 1 or 0)) * FanTheHammer.rank) and (((not self.vanish_condition or not Vanish:Ready()) and not ShadowDance:Ready()) or Player.stealthed or not Crackshot.known or FanTheHammer.rank <= 1))
			)) or
			(not FanTheHammer.known and (
				Player.energy.deficit > (Player.energy.regen * 1.5) or
				Player.combo_points.deficit <= (1 + (RollTheBones.Broadside:Up() and 1 or 0)) or
				QuickDraw.known or
				(Audacity.known and Audacity:Down())
			))
		))
	) then
		return PistolShot
	end
	if HiddenOpportunity.known and Ambush:Usable(0, true) then
		return Pool(Ambush)
	end
	if SinisterStrike:Usable(0, true) then
		return Pool(SinisterStrike)
	end
end

APL[SPEC.SUBTLETY].Main = function(self)
	if Player.health.pct < Opt.heal then
		if CrimsonVial:Usable() then
			UseExtra(CrimsonVial)
		end
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=apply_poison
actions.precombat+=/snapshot_stats
actions.precombat+=/variable,name=priority_rotation,value=priority_rotation
actions.precombat+=/variable,name=trinket_sync_slot,value=1,if=trinket.1.has_stat.any_dps&(!trinket.2.has_stat.any_dps|trinket.1.is.treacherous_transmitter|trinket.1.cooldown.duration>=trinket.2.cooldown.duration)
actions.precombat+=/variable,name=trinket_sync_slot,value=2,if=trinket.2.has_stat.any_dps&(!trinket.1.has_stat.any_dps|trinket.2.cooldown.duration>trinket.1.cooldown.duration)
actions.precombat+=/stealth
]]
		if Opt.poisons then
			if Player.poison.lethal[1] and Player.poison.lethal[1]:Usable() and Player.poison.lethal[1]:Remains() < 300 then
				return Player.poison.lethal[1]
			end
			if Player.poison.nonlethal[1] and Player.poison.nonlethal[1]:Usable() and Player.poison.nonlethal[1]:Remains() < 300 then
				return Player.poison.nonlethal[1]
			end
		end
		if Stealth:Usable() then
			return Stealth
		end
		if SliceAndDice:Usable() and SliceAndDice:Remains() < (4 * Player.combo_points.current) and Player.combo_points.current >= 2 then
			return SliceAndDice
		end
	end
--[[
actions=stealth
actions+=/variable,name=stealth,value=buff.shadow_dance.up|buff.stealth.up|buff.vanish.up
actions+=/variable,name=targets,value=spell_targets.shuriken_storm
actions+=/variable,name=skip_rupture,value=buff.shadow_dance.up|!buff.slice_and_dice.up|buff.darkest_night.up|variable.targets>=8&!talent.replicating_shadows&talent.unseen_blade
actions+=/variable,name=maintenance,value=(dot.rupture.ticking|variable.skip_rupture)&buff.slice_and_dice.up
actions+=/variable,name=secret,value=buff.shadow_dance.up|(cooldown.flagellation.remains<40&cooldown.flagellation.remains>20&talent.death_perception)
actions+=/variable,name=racial_sync,value=(buff.shadow_blades.up&buff.shadow_dance.up)|!talent.shadow_blades&buff.symbols_of_death.up|fight_remains<20
actions+=/variable,name=shd_cp,value=combo_points<=1|buff.darkest_night.up&combo_points>=7|effective_combo_points>=6&talent.unseen_blade
actions+=/call_action_list,name=cds
actions+=/call_action_list,name=race
actions+=/call_action_list,name=item
actions+=/call_action_list,name=stealth_cds,if=!variable.stealth
actions+=/call_action_list,name=finish,if=!buff.darkest_night.up&effective_combo_points>=6|buff.darkest_night.up&combo_points==cp_max_spend
actions+=/call_action_list,name=build
actions+=/call_action_list,name=fill,if=!variable.stealth
]]
	self.priority_rotation = Opt.priority_rotation and Player.enemies >= 2
	self.skip_rupture = not Rupture.known or ShadowDance:Up() or SliceAndDice:Down() or (DarkestNight.known and DarkestNight:Up()) or (Player.enemies >= 8 and not ReplicatingShadows.known and UnseenBlade.known)
	self.maintenance = (Rupture:Ticking() > 0 or self.skip_rupture) and SliceAndDice:Up()
	self.secret = SecretTechnique.known and (ShadowDance:Up() or (Flagellation.known and DeathPerception.known and between(Flagellation:Cooldown(), 20, 40)))
	self.shd_cp = Player.combo_points.current <= 1 or (DarkestNight.known and Player.combo_points.current >= 7 and DarkestNight:Up()) or (UnseenBlade.known and Player.combo_points.effective >= 6)
	if Racial.Shadowmeld.known and Stealth:Usable() and Racial.Shadowmeld:Up() then
		return Stealth
	end
	self:cds()
	self:item()
	local apl
	if not Player.stealthed then
		apl = self:stealth_cds()
		if apl then return apl end
	end
	if (
		(not DarkestNight.known and Player.combo_points.effective >= 6) or
		(DarkestNight.known and (Player.combo_points.current >= Player.combo_points.max_spend or (Player.combo_points.effective >= 6 and DarkestNight:Down())))
	) then
		apl = self:finish()
		if apl then return apl end
	end
	apl = self:build()
	if apl then return apl end
	if not Player.stealthed then
		apl = self:fill()
		if apl then return apl end
	end
end

APL[SPEC.SUBTLETY].cds = function(self)
--[[
actions.cds=cold_blood,if=cooldown.secret_technique.up&buff.shadow_dance.up&combo_points>=6&variable.secret&buff.flagellation_persist.up
actions.cds+=/potion,if=buff.bloodlust.react|fight_remains<30|buff.flagellation_buff.up
actions.cds+=/symbols_of_death,if=(buff.symbols_of_death.remains<=3&variable.maintenance&(!talent.flagellation|cooldown.flagellation.remains>=30-15*!talent.death_perception&cooldown.secret_technique.remains<8|!talent.death_perception)|fight_remains<=15)
actions.cds+=/shadow_blades,if=variable.maintenance&variable.shd_cp&buff.shadow_dance.up&!buff.premeditation.up
actions.cds+=/thistle_tea,if=buff.shadow_dance.remains>2&!buff.thistle_tea.up
actions.cds+=/flagellation,if=combo_points>=5&cooldown.shadow_blades.remains<=3|fight_remains<=25
]]
	if ColdBlood:Usable() and Player.combo_points.current >= 6 and ShadowDance:Up() and (not SecretTechnique.known or (self.secret and SecretTechnique:Ready())) and (
		not Flagellation.known or
		Flagellation.Persist:Up() or
		(Flagellation.Buff:Down() and not Flagellation:Ready(35)) or
		(Target.boss and Target.timeToDie < (Flagellation:Cooldown() + 12) and (Flagellation.Buff:Down() or Target.timeToDie < (Flagellation.Buff:Remains() + 4)))
	) then
		return UseCooldown(ColdBlood)
	end
	if self.maintenance and SymbolsOfDeath:Usable() and SymbolsOfDeath:Remains() <= 3 and (
		not Flagellation.known or
		not DeathPerception.known or
		not Flagellation:Ready(30 - (not DeathPerception.known and SecretTechnique:Ready(8) and 15 or 0)) or
		(Target.boss and Target.timeToDie < 15)
	) then
		return UseCooldown(SymbolsOfDeath)
	end
	if self.maintenance and self.shd_cp and ShadowBlades:Usable() and ShadowBlades:Down() and ShadowDance:Up() and (not Premeditation.known or Premeditation:Down()) and (not Flagellation.known or Flagellation.Buff:Up() or Flagellation.Persist:Up() or not Flagellation:Ready(75) or (Target.boss and Target.timeToDie < 18)) then
		return UseCooldown(ShadowBlades)
	end
	if ThistleTea:Usable() and ThistleTea:Down() and (
		ShadowDance:Remains() > 2 or
		(Target.boss and Target.timeToDie < (6 * ThistleTea:Charges()))
	) then
		UseExtra(ThistleTea)
	end
	if Flagellation:Usable() and Player.combo_points.current >= 5 and Target.timeToDie > 10 and (not ShadowBlades.known or ShadowBlades:Up() or ShadowBlades:Ready(3) or not ShadowBlades:Ready(80) or (Target.boss and Target.timeToDie < 25)) then
		return UseCooldown(Flagellation)
	end
end

APL[SPEC.SUBTLETY].item = function(self)
--[[
actions.item=use_item,name=treacherous_transmitter,if=cooldown.flagellation.remains<=2|fight_remains<=15
actions.item+=/do_treacherous_transmitter_task,if=buff.shadow_dance.up|fight_remains<=15
actions.item+=/use_item,name=imperfect_ascendancy_serum,use_off_gcd=1,if=dot.rupture.ticking&buff.flagellation_buff.up
actions.item+=/use_item,name=mad_queens_mandate,if=(!talent.lingering_darkness|buff.lingering_darkness.up|equipped.treacherous_transmitter)&(!equipped.treacherous_transmitter|trinket.treacherous_transmitter.cooldown.remains>20)|fight_remains<=15
actions.item+=/use_items,slots=trinket1,if=(variable.trinket_sync_slot=1&(buff.shadow_blades.up|fight_remains<=20)|(variable.trinket_sync_slot=2&(!trinket.2.cooldown.ready&!buff.shadow_blades.up&cooldown.shadow_blades.remains>20))|!variable.trinket_sync_slot)
actions.item+=/use_items,slots=trinket2,if=(variable.trinket_sync_slot=2&(buff.shadow_blades.up|fight_remains<=20)|(variable.trinket_sync_slot=1&(!trinket.1.cooldown.ready&!buff.shadow_blades.up&cooldown.shadow_blades.remains>20))|!variable.trinket_sync_slot)
]]
	if Opt.trinket and not (Stealth:Up() or Vanish:Up() or Racial.Shadowmeld:Up()) and (
		(Target.boss and Target.timeToDie < 20) or
		(ShadowBlades.known and ShadowBlades:Up()) or
		(Flagellation.known and (Flagellation.Buff:Up() or Flagellation.Persist:Up()))
	) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.SUBTLETY].stealth_cds = function(self)
--[[
actions.stealth_cds=shadow_dance,if=variable.shd_cp&variable.maintenance&cooldown.secret_technique.remains<=24&(buff.symbols_of_death.remains>=6|buff.shadow_blades.remains>=6)|fight_remains<=10
actions.stealth_cds+=/vanish,if=energy>=40&!buff.subterfuge.up&effective_combo_points<=3
actions.stealth_cds+=/shadowmeld,if=energy>=40&combo_points.deficit>=3
]]
	if ShadowDance:Usable() and (
		(self.shd_cp and self.maintenance and (not SecretTechnique.known or SecretTechnique:Ready(24)) and (SymbolsOfDeath:Remains() >= 6 or ShadowBlades:Remains() >= 6)) or
		(Target.boss and Target.timeToDie < 10)
	) then
		return UseCooldown(ShadowDance)
	end
	if Vanish:Usable() and Player.energy.current >= 40 and Player.combo_points.effective <= 3 and Subterfuge:Down() then
		return UseExtra(Vanish)
	end
	if Racial.Shadowmeld:Usable() and Player.energy.current >= 40 and Player.combo_points.deficit >= 3 then
		return UseExtra(Racial.Shadowmeld)
	end
end

APL[SPEC.SUBTLETY].fill = function(self)
--[[
actions.fill=arcane_torrent,if=energy.deficit>=15+energy.regen
actions.fill+=/arcane_pulse
actions.fill+=/lights_judgment
actions.fill+=/bag_of_tricks
]]

end

APL[SPEC.SUBTLETY].finish = function(self)
--[[
actions.finish=secret_technique,if=variable.secret
actions.finish+=/rupture,if=!variable.skip_rupture&(!dot.rupture.ticking|refreshable)&target.time_to_die-remains>6
actions.finish+=/rupture,cycle_targets=1,if=!variable.skip_rupture&!variable.priority_rotation&&target.time_to_die>=(2*combo_points)&refreshable&variable.targets>=2
actions.finish+=/rupture,if=talent.unseen_blade&cooldown.flagellation.remains<10
actions.finish+=/coup_de_grace,if=debuff.fazed.up
actions.finish+=/black_powder,if=!variable.priority_rotation&variable.maintenance&((variable.targets>=2&talent.deathstalkers_mark&(!buff.darkest_night.up|buff.shadow_dance.up&variable.targets>=5))|talent.unseen_blade&variable.targets>=7)
actions.finish+=/eviscerate
actions.finish+=/coup_de_grace
]]
	if self.secret and SecretTechnique:Usable(0, true) then
		return Pool(SecretTechnique)
	end
	if Rupture:Usable(0, true) and (
		(not self.skip_rupture and (Rupture:Ticking() == 0 or Rupture:Refreshable()) and Target.timeToDie > (Rupture:Remains() + (3 * Rupture:TickTime()))) or
		(not self.skip_rupture and not self.priority_rotation and Player.enemies >= 2 and Rupture:Refreshable() and Target.timeToDie >= (2 * Player.combo_points.current)) or
		(UnseenBlade.known and Flagellation.known and Flagellation:Ready(10) and Rupture:Remains() < 24 and Target.timeToDie > Rupture:Remains())
	) then
		return Pool(Rupture)
	end
	if CoupDeGrace:Usable(0, true) and Fazed:Up() then
		return Pool(CoupDeGrace)
	end
	if BlackPowder:Usable(0, true) and not self.priority_rotation and self.maintenance and (
		(Player.enemies >= 2 and DeathstalkersMark.known and (DarkestNight:Down() or (ShadowDance:Up() and Player.enemies >= 5))) or
		(UnseenBlade.known and Player.enemies >= 7)
	) then
		return Pool(BlackPowder)
	end
	if Eviscerate:Usable(0, true) then
		return Pool(Eviscerate)
	end
	if CoupDeGrace:Usable(0, true) then
		return Pool(CoupDeGrace)
	end
end

APL[SPEC.SUBTLETY].build = function(self)
--[[
actions.build=shadowstrike,cycle_targets=1,if=debuff.find_weakness.remains<=2&variable.targets=2&talent.unseen_blade|!used_for_danse&!talent.premeditation
actions.build+=/shuriken_tornado,if=buff.lingering_darkness.up|talent.deathstalkers_mark&cooldown.shadow_blades.remains>=32&variable.targets>=3|talent.unseen_blade&buff.symbols_of_death.up&variable.targets>=4
actions.build+=/shuriken_storm,if=buff.clear_the_witnesses.up&variable.targets>=2
actions.build+=/shadowstrike,cycle_targets=1,if=talent.deathstalkers_mark&!debuff.deathstalkers_mark.up&variable.targets>=3&(buff.shadow_blades.up|buff.premeditation.up|talent.the_rotten)
actions.build+=/shuriken_storm,if=talent.deathstalkers_mark&!buff.premeditation.up&variable.targets>=(2+3*buff.shadow_dance.up)|buff.clear_the_witnesses.up&!buff.symbols_of_death.up|buff.flawless_form.up&variable.targets>=3&!variable.stealth|talent.unseen_blade&buff.the_rotten.stack=1&variable.targets>=7&buff.shadow_dance.up
actions.build+=/shadowstrike
actions.build+=/goremaws_bite,if=combo_points.deficit>=3
actions.build+=/gloomblade
actions.build+=/backstab
]]
	if Shadowstrike:Usable() and (
		(UnseenBlade.known and FindWeakness:Remains() <= 2 and Player.enemies == 2) or
		(not Premeditation.known and not DanseMacabre:UsedFor(Shadowstrike))
	) then
		return Shadowstrike
	end
	if ShurikenTornado:Usable() and (
		(LingeringDarkness.known and LingeringDarkness:Up()) or
		(DeathstalkersMark.known and Player.enemies >= 3 and not ShadowBlades:Ready(32)) or
		(UnseenBlade.known and Player.enemies >= 4 and SymbolsOfDeath:Up())
	) then
		UseCooldown(ShurikenTornado)
	end
	if ShurikenStorm:Usable() and Player.enemies >= 2 and ClearTheWitnesses:Up() then
		return ShurikenStorm
	end
	if DeathstalkersMark.known and Shadowstrike:Usable() and DeathstalkersMark:Down() and Player.enemies >= 3 and (TheRotten.known or (Premeditation.known and Premeditation:Up()) or ShadowBlades:Up()) then
		return Shadowstrike
	end
	if ShurikenStorm:Usable() and (
		(DeathstalkersMark.known and Premeditation:Down() and Player.enemies >= (2 + (ShadowDance:Up() and 3 or 0))) or
		(ClearTheWitnesses:Up() and SymbolsOfDeath:Down()) or
		(FlawlessForm.known and FlawlessForm:Up() and Player.enemies >= 3 and not Player.stealthed) or
		(UnseenBlade.known and TheRotten.known and TheRotten:Stack() == 1 and Player.enemies >= 7 and ShadowDance:Up())
	) then
		return ShurikenStorm
	end
	if Shadowstrike:Usable() then
		return Shadowstrike
	end
	if GoremawsBite:Usable() and Player.combo_points.deficit >= 3 then
		return Gloomblade
	end
	if Gloomblade:Usable() then
		return Gloomblade
	end
	if Backstab:Usable() then
		return Backstab
	end
end

APL.Interrupt = function(self)
	if Kick:Usable() then
		return Kick
	end
	if CheapShot:Usable() then
		return CheapShot
	end
	if Gouge:Usable() then
		return Gouge
	end
	if KidneyShot:Usable() then
		return KidneyShot
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i, button in next, self.buttons do
		glow = button['glow' .. ADDON]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if Opt.glow.blizzard or not LibStub then
		return
	end
	local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
	if lib then
		lib.ShowOverlayGlow = function(...)
			return lib.HideOverlayGlow(...)
		end
	end
end

function UI:ScanActionButtons()
	wipe(self.buttons)
	if Bartender4 then
		for i = 1, 120 do
			self.buttons[#self.buttons + 1] = _G['BT4Button' .. i]
		end
		for i = 1, 10 do
			self.buttons[#self.buttons + 1] = _G['BT4PetButton' .. i]
		end
		return
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				self.buttons[#self.buttons + 1] = _G['ElvUI_Bar' .. b .. 'Button' .. i]
			end
		end
		return
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				self.buttons[#self.buttons + 1] = _G['LUIBarBottom' .. b .. 'Button' .. i]
				self.buttons[#self.buttons + 1] = _G['LUIBarLeft' .. b .. 'Button' .. i]
				self.buttons[#self.buttons + 1] = _G['LUIBarRight' .. b .. 'Button' .. i]
			end
		end
		return
	end
	if Dominos then
		for i = 1, 60 do
			self.buttons[#self.buttons + 1] = _G['DominosActionButton' .. i]
		end
		-- fallthrough because Dominos re-uses Blizzard action buttons
	end
	for i = 1, 12 do
		self.buttons[#self.buttons + 1] = _G['ActionButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarLeftButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarRightButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarBottomLeftButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarBottomRightButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar5Button' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar6Button' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar7Button' .. i]
	end
	for i = 1, 10 do
		self.buttons[#self.buttons + 1] = _G['PetActionButton' .. i]
	end
end

function UI:CreateOverlayGlows()
	local glow
	for i, button in next, self.buttons do
		glow = button['glow' .. ADDON] or CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
		glow:Hide()
		glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
		glow.button = button
		button['glow' .. ADDON] = glow
	end
	self:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, action
	for _, slot in next, self.action_slots do
		action = slot.action
		for _, button in next, slot.buttons do
			glow = button['glow' .. ADDON]
			if action and button:IsVisible() and (
				(Opt.glow.main and action == Player.main) or
				(Opt.glow.cooldown and action == Player.cd) or
				(Opt.glow.interrupt and action == Player.interrupt) or
				(Opt.glow.extra and action == Player.extra)
			) then
				if not glow:IsVisible() then
					glow:Show()
					if Opt.glow.animation then
						glow.ProcStartAnim:Play()
					else
						glow.ProcLoop:Play()
					end
				end
			elseif glow:IsVisible() then
				if glow.ProcStartAnim:IsPlaying() then
					glow.ProcStartAnim:Stop()
				end
				if glow.ProcLoop:IsPlaying() then
					glow.ProcLoop:Stop()
				end
				glow:Hide()
			end
		end
	end
end

UI.KeybindPatterns = {
	['ALT%-'] = 'a-',
	['CTRL%-'] = 'c-',
	['SHIFT%-'] = 's-',
	['META%-'] = 'm-',
	['NUMPAD'] = 'NP',
	['PLUS'] = '%+',
	['MINUS'] = '%-',
	['MULTIPLY'] = '%*',
	['DIVIDE'] = '%/',
	['BACKSPACE'] = 'BS',
	['BUTTON'] = 'MB',
	['CLEAR'] = 'Clr',
	['DELETE'] = 'Del',
	['END'] = 'End',
	['HOME'] = 'Home',
	['INSERT'] = 'Ins',
	['MOUSEWHEELDOWN'] = 'MwD',
	['MOUSEWHEELUP'] = 'MwU',
	['PAGEDOWN'] = 'PgDn',
	['PAGEUP'] = 'PgUp',
	['CAPSLOCK'] = 'Caps',
	['NUMLOCK'] = 'NumL',
	['SCROLLLOCK'] = 'ScrL',
	['SPACEBAR'] = 'Space',
	['SPACE'] = 'Space',
	['TAB'] = 'Tab',
	['DOWNARROW'] = 'Down',
	['LEFTARROW'] = 'Left',
	['RIGHTARROW'] = 'Right',
	['UPARROW'] = 'Up',
}

function UI:GetButtonKeybind(button)
	local bind = button.bindingAction or (button.config and button.config.keyBoundTarget)
	if bind then
		local key = GetBindingKey(bind)
		if key then
			key = key:gsub(' ', ''):upper()
			for pattern, short in next, self.KeybindPatterns do
				key = key:gsub(pattern, short)
			end
			return key
		end
	end
end

function UI:GetActionFromID(actionId)
	local actionType, id, subType = GetActionInfo(actionId)
	if id and type(id) == 'number' and id > 0 then
		if (actionType == 'item' or (actionType == 'macro' and subType == 'item')) then
			return InventoryItems.byItemId[id]
		elseif (actionType == 'spell' or (actionType == 'macro' and subType == 'spell')) then
			return Abilities.bySpellId[id]
		end
	end
end

function UI:UpdateActionSlot(actionId)
	local slot = self.action_slots[actionId]
	if not slot then
		return
	end
	local action = self:GetActionFromID(actionId)
	if action ~= slot.action then
		if slot.action then
			slot.action.keybinds[actionId] = nil
		end
		slot.action = action
	end
	if not action then
		return
	end
	for _, button in next, slot.buttons do
		action.keybinds[actionId] = self:GetButtonKeybind(button)
		if action.keybinds[actionId] then
			return
		end
	end
	action.keybinds[actionId] = nil
end

function UI:UpdateBindings()
	for _, item in next, InventoryItems.all do
		wipe(item.keybinds)
	end
	for _, ability in next, Abilities.all do
		wipe(ability.keybinds)
	end
	for actionId in next, self.action_slots do
		self:UpdateActionSlot(actionId)
	end
end

function UI:ScanActionSlots()
	wipe(self.action_slots)
	local actionId, buttons
	for _, button in next, self.buttons do
		actionId = (
			(button._state_type == 'action' and button._state_action) or
			(button.CalculateAction and button:CalculateAction()) or
			(button:GetAttribute('action'))
		) or 0
		if actionId > 0 then
			if not self.action_slots[actionId] then
				self.action_slots[actionId] = {
					buttons = {},
				}
			end
			buttons = self.action_slots[actionId].buttons
			buttons[#buttons + 1] = button
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	assassinPanel:SetMovable(not Opt.snap)
	assassinPreviousPanel:SetMovable(not Opt.snap)
	assassinCooldownPanel:SetMovable(not Opt.snap)
	assassinInterruptPanel:SetMovable(not Opt.snap)
	assassinExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		assassinPanel:SetUserPlaced(true)
		assassinPreviousPanel:SetUserPlaced(true)
		assassinCooldownPanel:SetUserPlaced(true)
		assassinInterruptPanel:SetUserPlaced(true)
		assassinExtraPanel:SetUserPlaced(true)
	end
	assassinPanel:EnableMouse(draggable or Opt.aoe)
	assassinPanel.button:SetShown(Opt.aoe)
	assassinPreviousPanel:EnableMouse(draggable)
	assassinCooldownPanel:EnableMouse(draggable)
	assassinInterruptPanel:EnableMouse(draggable)
	assassinExtraPanel:EnableMouse(draggable)
end

function UI:UpdateAlpha()
	assassinPanel:SetAlpha(Opt.alpha)
	assassinPreviousPanel:SetAlpha(Opt.alpha)
	assassinCooldownPanel:SetAlpha(Opt.alpha)
	assassinInterruptPanel:SetAlpha(Opt.alpha)
	assassinExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	assassinPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	assassinPanel.text:SetScale(Opt.scale.main)
	assassinPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	assassinCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	assassinCooldownPanel.text:SetScale(Opt.scale.cooldown)
	assassinInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	assassinExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	assassinPreviousPanel:ClearAllPoints()
	assassinPreviousPanel:SetPoint('TOPRIGHT', assassinPanel, 'BOTTOMLEFT', -3, 40)
	assassinCooldownPanel:ClearAllPoints()
	assassinCooldownPanel:SetPoint('TOPLEFT', assassinPanel, 'BOTTOMRIGHT', 3, 40)
	assassinInterruptPanel:ClearAllPoints()
	assassinInterruptPanel:SetPoint('BOTTOMLEFT', assassinPanel, 'TOPRIGHT', 3, -21)
	assassinExtraPanel:ClearAllPoints()
	assassinExtraPanel:SetPoint('BOTTOMRIGHT', assassinPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.ASSASSINATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.OUTLAW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.SUBTLETY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ASSASSINATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.OUTLAW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.SUBTLETY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		assassinPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		assassinPanel:ClearAllPoints()
		assassinPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.ASSASSINATION and Opt.hide.assassination) or
		   (Player.spec == SPEC.OUTLAW and Opt.hide.outlaw) or
		   (Player.spec == SPEC.SUBTLETY and Opt.hide.subtlety))
end

function UI:Disappear()
	assassinPanel:Hide()
	assassinPanel.icon:Hide()
	assassinPanel.border:Hide()
	assassinCooldownPanel:Hide()
	assassinInterruptPanel:Hide()
	assassinExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	self:UpdateGlows()
end

function UI:Reset()
	assassinPanel:ClearAllPoints()
	assassinPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_center, text_tl, text_tr, text_bl, text_cd_center, text_cd_tr
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
		if Opt.keybinds then
			for _, bind in next, Player.main.keybinds do
				text_tr = bind
				break
			end
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd_center = format('%.1f', react)
			end
		end
		if Opt.keybinds then
			for _, bind in next, Player.cd.keybinds do
				text_cd_tr = bind
				break
			end
		end
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			text_center = format('POOL\n%d', deficit)
			dim = Opt.dimmer
		end
	end
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if assassinPanel.text.multiplier_diff and not text_center then
		if assassinPanel.text.multiplier_diff >= 0 then
			text_center = format('|cFF00FF00+%d%%', assassinPanel.text.multiplier_diff * 100)
		elseif assassinPanel.text.multiplier_diff < 0 then
			text_center = format('|cFFFF0000%d%%', assassinPanel.text.multiplier_diff * 100)
		end
	else
		assassinPanel.text.center:SetTextColor(1, 1, 1)
	end
	if Player.danse_stacks > 0 then
		text_tl = Player.danse_stacks
	end
	if Player.stealth_remains > 0 then
		text_bl = format('%.1fs', Player.stealth_remains)
	end
	if border ~= assassinPanel.border.overlay then
		assassinPanel.border.overlay = border
		assassinPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	assassinPanel.dimmer:SetShown(dim)
	assassinPanel.text.center:SetText(text_center)
	assassinPanel.text.tl:SetText(text_tl)
	assassinPanel.text.tr:SetText(text_tr)
	assassinPanel.text.bl:SetText(text_bl)
	assassinCooldownPanel.dimmer:SetShown(dim_cd)
	assassinCooldownPanel.text.center:SetText(text_cd_center)
	assassinCooldownPanel.text.tr:SetText(text_cd_tr)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		assassinPanel.icon:SetTexture(Player.main.icon)
		if Opt.multipliers and Player.main.NextMultiplier then
			assassinPanel.text.multiplier_diff = Player.main:NextMultiplier() - Player.main:Multiplier()
		else
			assassinPanel.text.multiplier_diff = nil
		end
		Player.main_freecast = Player.main:Free()
	end
	if Player.cd then
		assassinCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			assassinCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
		end
	end
	if Player.extra then
		assassinExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			assassinInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			assassinInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		assassinInterruptPanel.icon:SetShown(Player.interrupt)
		assassinInterruptPanel.border:SetShown(Player.interrupt)
		assassinInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and assassinPreviousPanel.ability then
		if (Player.time - assassinPreviousPanel.ability.last_used) > 10 then
			assassinPreviousPanel.ability = nil
			assassinPreviousPanel:Hide()
		end
	end

	assassinPanel.icon:SetShown(Player.main)
	assassinPanel.border:SetShown(Player.main)
	assassinCooldownPanel:SetShown(Player.cd)
	assassinExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Assassin
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Assassin1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	local uid = ToUID(dstGUID)
	if not uid or Target.Dummies[uid] then
		return
	end
	TrackedAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

--local UnknownSpell = {}

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
--[[
		if not UnknownSpell[event] then
			UnknownSpell[event] = {}
		end
		if not UnknownSpell[event][spellId] then
			UnknownSpell[event][spellId] = true
			log(format('%.3f EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d FROM %s ON %s', Player.time, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0, srcGUID, dstGUID))
		end
]]
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
			if RollTheBones.known and RollTheBones.Buffs[ability] then
				ability.trigger = RollTheBones.next_trigger
			end
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitEffectiveLevel(unitId)
		Player.energy.max = UnitPowerMax(unitId, 3)
		Player.combo_points.max = UnitPowerMax(unitId, 4)
	end
end

function Events:UNIT_POWER_UPDATE(unitId, powerType)
	if unitId == 'player' and powerType == 'COMBO_POINTS' then
		Player.combo_points.current = UnitPower(unitId, 4)
		Player.combo_points.deficit = Player.combo_points.max - Player.combo_points.current
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.next_combo_points then
		ability.next_combo_points = UnitPower('player', 4)
		ability.next_applied_by = ability
	end
	if ability.NextMultiplier then
		ability.next_multiplier = ability:NextMultiplier()
	end
	if RollTheBones.known and (ability == RollTheBones or (CountTheOdds.known and CountTheOdds.triggers[ability])) then
		RollTheBones.next_trigger = ability
	end
	if Supercharger.known and Supercharger.finishers[ability] and Player.combo_points.supercharged[Player.combo_points.current] then
		Supercharger[Player.combo_points.current].consume_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
	if Supercharger.known then
		if (
			(Player.spec == SPEC.ASSASSINATION and ability == Shiv) or
			(Player.spec == SPEC.OUTLAW and ability == RollTheBones) or
			(Player.spec == SPEC.SUBTLETY and ability == SymbolsOfDeath)
		) then
			for i = 1, 7 do
				Supercharger[i].consume_castGUID = nil
				Supercharger[i].consumed = false
			end
			return
		end
		for i = 1, 7 do
			if castGUID == Supercharger[i].consume_castGUID then
				Supercharger[i].consume_castGUID = nil
				Supercharger[i].consumed = true
			end
		end
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		assassinPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe and (Player.time - Player.stealth_time) > 3 then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for _, i in next, InventoryItems.all do
		i.name, _, _, _, _, _, _, _, equipType, i.icon = GetItemInfo(i.itemId or 0)
		i.can_use = i.name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, i.equip_slot = Player:Equipped(i.itemId)
			if i.equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', i.equip_slot)
			end
			i.can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[i.itemId] then
			i.can_use = false
		end
	end

	Player.set_bonus.t33 = (Player:Equipped(212036) and 1 or 0) + (Player:Equipped(212037) and 1 or 0) + (Player:Equipped(212038) and 1 or 0) + (Player:Equipped(212039) and 1 or 0) + (Player:Equipped(212041) and 1 or 0)

	Player:ResetSwing(true, true)
	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	assassinPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	Events:UPDATE_BINDINGS()
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(61304)
		end
		assassinPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED(slot)
	if not slot or slot < 1 then
		UI:ScanActionSlots()
		UI:UpdateBindings()
	else
		UI:UpdateActionSlot(slot)
	end
	UI:UpdateGlows()
end

function Events:ACTIONBAR_PAGE_CHANGED()
	C_Timer.After(0, function()
		Events:ACTIONBAR_SLOT_CHANGED(0)
	end)
end
Events.UPDATE_BONUS_ACTIONBAR = Events.ACTIONBAR_PAGE_CHANGED

function Events:UPDATE_BINDINGS()
	UI:UpdateBindings()
end
Events.GAME_PAD_ACTIVE_CHANGED = Events.UPDATE_BINDINGS

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

assassinPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

assassinPanel:SetScript('OnUpdate', function(self, elapsed)
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

assassinPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	assassinPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'key') or startsWith(msg[1], 'bind') then
		if msg[2] then
			Opt.keybinds = msg[2] == 'on'
		end
		return Status('Show keybinding text on main ability icon (topright)', Opt.keybinds)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if startsWith(msg[1], 'hide') or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'a') then
				Opt.hide.assassination = not Opt.hide.assassination
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Assassination specialization', not Opt.hide.assassination)
			end
			if startsWith(msg[2], 'o') then
				Opt.hide.outlaw = not Opt.hide.outlaw
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Outlaw specialization', not Opt.hide.outlaw)
			end
			if startsWith(msg[2], 's') then
				Opt.hide.subtlety = not Opt.hide.subtlety
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Subtlety specialization', not Opt.hide.subtlety)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000assassination|r/|cFFFFD000outlaw|r/|cFFFFD000subtlety|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal .. '%')
	end
	if startsWith(msg[1], 'mu') then
		if msg[2] then
			Opt.multipliers = msg[2] == 'on'
		end
		return Status('Show DoT multiplier differences (center)', Opt.multipliers)
	end
	if startsWith(msg[1], 'poi') then
		if msg[2] then
			Opt.poisons = msg[2] == 'on'
		end
		return Status('Show a reminder for poisons (5 minutes outside combat)', Opt.poisons)
	end
	if startsWith(msg[1], 'pri') then
		if msg[2] then
			Opt.priority_rotation = msg[2] == 'on'
		end
		return Status('Use "priority rotation" mode (off by default)', Opt.priority_rotation)
	end
	if startsWith(msg[1], 'va') then
		if msg[2] then
			Opt.vanish_solo = msg[2] == 'on'
		end
		return Status('Use Vanish and Shadowmeld while solo (off by default, use for training dummies)', Opt.vanish_solo)
	end
	if msg[1] == 'rtb' or startsWith(msg[1], 'roll') then
		if msg[2] then
			if msg[2] == 'on' or msg[2] == 'off' then
				Opt.rtb_values.enabled = msg[2] == 'on'
				return Status(RollTheBones.name .. ' value-based rerolls', Opt.rtb_values.enabled)
			end
			if startsWith(msg[2], 'th') or startsWith(msg[2], 'va') then
				Opt.rtb_values.threshold = clamp(tonumber(msg[3]) or 16, 0, 50)
				if msg[4] then
					Opt.rtb_values.loaded_dice = clamp(tonumber(msg[4]) or 7, 0, 50)
				end
				return Status('Reroll if total value of current buffs is below', Opt.rtb_values.threshold .. ' + ' .. Opt.rtb_values.loaded_dice, '(' .. LoadedDice.name .. ' modifier)')
			end
			if startsWith(msg[2], 'br') then
				Opt.rtb_values.broadside = clamp(tonumber(msg[3]) or 10, 0, 20)
				return Status(RollTheBones.Broadside.name .. ' value', Opt.rtb_values.broadside)
			end
			if startsWith(msg[2], 'tr') then
				Opt.rtb_values.true_bearing = clamp(tonumber(msg[3]) or 11, 0, 20)
				return Status(RollTheBones.TrueBearing.name .. ' value', Opt.rtb_values.true_bearing)
			end
			if startsWith(msg[2], 'ru') then
				Opt.rtb_values.ruthless_precision = clamp(tonumber(msg[3]) or 9, 0, 20)
				return Status(RollTheBones.RuthlessPrecision.name .. ' value', Opt.rtb_values.ruthless_precision)
			end
			if startsWith(msg[2], 'sk') then
				Opt.rtb_values.skull_and_crossbones = clamp(tonumber(msg[3]) or 8, 0, 20)
				return Status(RollTheBones.SkullAndCrossbones.name .. ' value', Opt.rtb_values.skull_and_crossbones)
			end
			if startsWith(msg[2], 'bu') then
				Opt.rtb_values.buried_treasure = clamp(tonumber(msg[3]) or 4, 0, 20)
				return Status(RollTheBones.BuriedTreasure.name .. ' value', Opt.rtb_values.buried_treasure)
			end
			if startsWith(msg[2], 'gr') then
				Opt.rtb_values.grand_melee = clamp(tonumber(msg[3]) or 3, 0, 20)
				if msg[4] then
					Opt.rtb_values.grand_melee_aoe = clamp(tonumber(msg[4]) or 2, 0, 20)
				end
				return Status(RollTheBones.GrandMelee.name .. ' value', Opt.rtb_values.grand_melee .. ' + ' .. Opt.rtb_values.grand_melee_aoe, '(aoe modifier)')
			end
		end
		Status(RollTheBones.name .. ' value-based rerolls', Opt.rtb_values.enabled)
		return Status('Possible configurable options', '|cFF00C000on|r/|cFFC00000off|r/|cFFFFD000threshold|r/|cFFFFD000broadside|r/|cFFFFD000true|r/|cFFFFD000ruthless|r/|cFFFFD000skull|r/|cFFFFD000buried|r/|cFFFFD000grand|r')
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'keybind |cFF00C000on|r/|cFFC00000off|r - show keybinding text on main ability icon (topright)',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000assassination|r/|cFFFFD000outlaw|r/|cFFFFD000subtlety|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
		'multipliers |cFF00C000on|r/|cFFC00000off|r - show DoT multiplier differences (center)',
		'poisons |cFF00C000on|r/|cFFC00000off|r - show a reminder for poisons (5 minutes outside combat)',
		'priority |cFF00C000on|r/|cFFC00000off|r - use "priority rotation" mode (off by default)',
		'vanish |cFF00C000on|r/|cFFC00000off|r - use Vanish and Shadowmeld while solo (off by default)',
		'rtb - run this command to see options for custom ' .. RollTheBones.name ..  ' reroll values',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Assassin1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
