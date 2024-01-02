local ADDON = 'Assassin'
if select(2, UnitClass('player')) ~= 'ROGUE' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
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
-- end useful functions

Assassin = {}
local Opt -- use this as a local table reference to Assassin

SLASH_Assassin1, SLASH_Assassin2 = '/ass', '/assassin'
BINDING_HEADER_ASSASSIN = ADDON

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
		poisons = true,
		last_poison = {
			lethal = false,
			nonlethal = false,
		},
		priority_rotation = false,
		vanish_solo = false,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
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
	trackAuras = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

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
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	energy = {
		current = 0,
		regen = 0,
		max = 100,
		deficit = 100,
	},
	combo_points = {
		current = 0,
		max = 5,
		max_spend = 5,
		deficit = 0,
		effective = 0,
		anima_charged = {},
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
		t29 = 0, -- Vault Delver's Toolkit
		t30 = 0, -- Lurking Specter's Shadeweave
		t31 = 0, -- Lucid Shadewalker's Silence
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	poison = {},
	stealthed = false,
	stealthed_nomeld = false,
	stealth_time = 0,
	stealth_remains = 0,
	danse_stacks = 0,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
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

local assassinPanel = CreateFrame('Frame', 'assassinPanel', UIParent)
assassinPanel:SetPoint('CENTER', 0, -169)
assassinPanel:SetFrameStrata('BACKGROUND')
assassinPanel:SetSize(64, 64)
assassinPanel:SetMovable(true)
assassinPanel:SetUserPlaced(true)
assassinPanel:RegisterForDrag('LeftButton')
assassinPanel:SetScript('OnDragStart', assassinPanel.StartMoving)
assassinPanel:SetScript('OnDragStop', assassinPanel.StopMovingOrSizing)
assassinPanel:Hide()
assassinPanel.icon = assassinPanel:CreateTexture(nil, 'BACKGROUND')
assassinPanel.icon:SetAllPoints(assassinPanel)
assassinPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinPanel.border = assassinPanel:CreateTexture(nil, 'ARTWORK')
assassinPanel.border:SetAllPoints(assassinPanel)
assassinPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
assassinPanel.border:Hide()
assassinPanel.dimmer = assassinPanel:CreateTexture(nil, 'BORDER')
assassinPanel.dimmer:SetAllPoints(assassinPanel)
assassinPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
assassinPanel.dimmer:Hide()
assassinPanel.swipe = CreateFrame('Cooldown', nil, assassinPanel, 'CooldownFrameTemplate')
assassinPanel.swipe:SetAllPoints(assassinPanel)
assassinPanel.swipe:SetDrawBling(false)
assassinPanel.swipe:SetDrawEdge(false)
assassinPanel.text = CreateFrame('Frame', nil, assassinPanel)
assassinPanel.text:SetAllPoints(assassinPanel)
assassinPanel.text.tl = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.tl:SetPoint('TOPLEFT', assassinPanel, 'TOPLEFT', 2.5, -3)
assassinPanel.text.tl:SetJustifyH('LEFT')
assassinPanel.text.tr = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.tr:SetPoint('TOPRIGHT', assassinPanel, 'TOPRIGHT', -2.5, -3)
assassinPanel.text.tr:SetJustifyH('RIGHT')
assassinPanel.text.bl = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.bl:SetPoint('BOTTOMLEFT', assassinPanel, 'BOTTOMLEFT', 2.5, 3)
assassinPanel.text.bl:SetJustifyH('LEFT')
assassinPanel.text.br = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.br:SetPoint('BOTTOMRIGHT', assassinPanel, 'BOTTOMRIGHT', -2.5, 3)
assassinPanel.text.br:SetJustifyH('RIGHT')
assassinPanel.text.center = assassinPanel.text:CreateFontString(nil, 'OVERLAY')
assassinPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.text.center:SetAllPoints(assassinPanel.text)
assassinPanel.text.center:SetJustifyH('CENTER')
assassinPanel.text.center:SetJustifyV('CENTER')
assassinPanel.button = CreateFrame('Button', nil, assassinPanel)
assassinPanel.button:SetAllPoints(assassinPanel)
assassinPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local assassinPreviousPanel = CreateFrame('Frame', 'assassinPreviousPanel', UIParent)
assassinPreviousPanel:SetFrameStrata('BACKGROUND')
assassinPreviousPanel:SetSize(64, 64)
assassinPreviousPanel:SetMovable(true)
assassinPreviousPanel:SetUserPlaced(true)
assassinPreviousPanel:RegisterForDrag('LeftButton')
assassinPreviousPanel:SetScript('OnDragStart', assassinPreviousPanel.StartMoving)
assassinPreviousPanel:SetScript('OnDragStop', assassinPreviousPanel.StopMovingOrSizing)
assassinPreviousPanel:Hide()
assassinPreviousPanel.icon = assassinPreviousPanel:CreateTexture(nil, 'BACKGROUND')
assassinPreviousPanel.icon:SetAllPoints(assassinPreviousPanel)
assassinPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinPreviousPanel.border = assassinPreviousPanel:CreateTexture(nil, 'ARTWORK')
assassinPreviousPanel.border:SetAllPoints(assassinPreviousPanel)
assassinPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local assassinCooldownPanel = CreateFrame('Frame', 'assassinCooldownPanel', UIParent)
assassinCooldownPanel:SetFrameStrata('BACKGROUND')
assassinCooldownPanel:SetSize(64, 64)
assassinCooldownPanel:SetMovable(true)
assassinCooldownPanel:SetUserPlaced(true)
assassinCooldownPanel:RegisterForDrag('LeftButton')
assassinCooldownPanel:SetScript('OnDragStart', assassinCooldownPanel.StartMoving)
assassinCooldownPanel:SetScript('OnDragStop', assassinCooldownPanel.StopMovingOrSizing)
assassinCooldownPanel:Hide()
assassinCooldownPanel.icon = assassinCooldownPanel:CreateTexture(nil, 'BACKGROUND')
assassinCooldownPanel.icon:SetAllPoints(assassinCooldownPanel)
assassinCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinCooldownPanel.border = assassinCooldownPanel:CreateTexture(nil, 'ARTWORK')
assassinCooldownPanel.border:SetAllPoints(assassinCooldownPanel)
assassinCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
assassinCooldownPanel.dimmer = assassinCooldownPanel:CreateTexture(nil, 'BORDER')
assassinCooldownPanel.dimmer:SetAllPoints(assassinCooldownPanel)
assassinCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
assassinCooldownPanel.dimmer:Hide()
assassinCooldownPanel.swipe = CreateFrame('Cooldown', nil, assassinCooldownPanel, 'CooldownFrameTemplate')
assassinCooldownPanel.swipe:SetAllPoints(assassinCooldownPanel)
assassinCooldownPanel.swipe:SetDrawBling(false)
assassinCooldownPanel.swipe:SetDrawEdge(false)
assassinCooldownPanel.text = assassinCooldownPanel:CreateFontString(nil, 'OVERLAY')
assassinCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinCooldownPanel.text:SetAllPoints(assassinCooldownPanel)
assassinCooldownPanel.text:SetJustifyH('CENTER')
assassinCooldownPanel.text:SetJustifyV('CENTER')
local assassinInterruptPanel = CreateFrame('Frame', 'assassinInterruptPanel', UIParent)
assassinInterruptPanel:SetFrameStrata('BACKGROUND')
assassinInterruptPanel:SetSize(64, 64)
assassinInterruptPanel:SetMovable(true)
assassinInterruptPanel:SetUserPlaced(true)
assassinInterruptPanel:RegisterForDrag('LeftButton')
assassinInterruptPanel:SetScript('OnDragStart', assassinInterruptPanel.StartMoving)
assassinInterruptPanel:SetScript('OnDragStop', assassinInterruptPanel.StopMovingOrSizing)
assassinInterruptPanel:Hide()
assassinInterruptPanel.icon = assassinInterruptPanel:CreateTexture(nil, 'BACKGROUND')
assassinInterruptPanel.icon:SetAllPoints(assassinInterruptPanel)
assassinInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinInterruptPanel.border = assassinInterruptPanel:CreateTexture(nil, 'ARTWORK')
assassinInterruptPanel.border:SetAllPoints(assassinInterruptPanel)
assassinInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
assassinInterruptPanel.swipe = CreateFrame('Cooldown', nil, assassinInterruptPanel, 'CooldownFrameTemplate')
assassinInterruptPanel.swipe:SetAllPoints(assassinInterruptPanel)
assassinInterruptPanel.swipe:SetDrawBling(false)
assassinInterruptPanel.swipe:SetDrawEdge(false)
local assassinExtraPanel = CreateFrame('Frame', 'assassinExtraPanel', UIParent)
assassinExtraPanel:SetFrameStrata('BACKGROUND')
assassinExtraPanel:SetSize(64, 64)
assassinExtraPanel:SetMovable(true)
assassinExtraPanel:SetUserPlaced(true)
assassinExtraPanel:RegisterForDrag('LeftButton')
assassinExtraPanel:SetScript('OnDragStart', assassinExtraPanel.StartMoving)
assassinExtraPanel:SetScript('OnDragStop', assassinExtraPanel.StopMovingOrSizing)
assassinExtraPanel:Hide()
assassinExtraPanel.icon = assassinExtraPanel:CreateTexture(nil, 'BACKGROUND')
assassinExtraPanel.icon:SetAllPoints(assassinExtraPanel)
assassinExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinExtraPanel.border = assassinExtraPanel:CreateTexture(nil, 'ARTWORK')
assassinExtraPanel.border:SetAllPoints(assassinExtraPanel)
assassinExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

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
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
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

function Ability:Remains(offGCD)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - (offGCD and 0 or Player.execute_remains))
		end
	end
	return 0
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
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	local remains = duration - (Player.ctime - start)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and count or 0
		end
	end
	return 0
end

function Ability:EnergyCost()
	return self.energy_cost
end

function Ability:CPCost()
	return self.cp_cost
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + (self.off_gcd and 0 or Player.execute_remains))) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
end

function Ability:CastRegen()
	return Player.energy.regen * self:CastTime() - self:EnergyCost()
end

function Ability:WontCapEnergy(reduction)
	return (Player.energy.current + self:CastRegen()) < (Player.energy.max - (reduction or 5))
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
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
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

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFocus():GetNodeID()
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
local Kick = Ability:Add(1766, false, true)
Kick.cooldown_duration = 15
Kick.triggers_gcd = false
local KidneyShot = Ability:Add(408, false, true)
KidneyShot.buff_duration = 1
KidneyShot.energy_cost = 25
KidneyShot.cp_cost = 1
local Rupture = Ability:Add(1943, false, true)
Rupture.buff_duration = 4
Rupture.energy_cost = 25
Rupture.cp_cost = 1
Rupture.tick_interval = 2
Rupture.hasted_ticks = true
Rupture:TrackAuras()
Rupture:AutoAoe(false, 'apply')
local ShadowDance = Ability:Add(185313, true, true, 185422)
ShadowDance.buff_duration = 6
ShadowDance.cooldown_duration = 60
ShadowDance.requires_charge = true
ShadowDance.triggers_gcd = false
local SinisterStrike = Ability:Add(193315, false, true)
SinisterStrike.energy_cost = 45
local SliceAndDice = Ability:Add(315496, true, true)
SliceAndDice.buff_duration = 6
SliceAndDice.energy_cost = 25
SliceAndDice.cp_cost = 1
local Stealth = Ability:Add(1784, true, true, 115191)
local Vanish = Ability:Add(1856, true, true, 11327)
Vanish.cooldown_duration = 120
Vanish.requires_charge = true
------ Talents
local Alacrity = Ability:Add(193539, true, true)
Alacrity.buff_duration = 20
local ColdBlood = Ability:Add(382245, true, true)
ColdBlood.buff_duration = 600
ColdBlood.cooldown_duration = 45
local DeeperStratagem = Ability:Add(193531, false, true)
local EchoingReprimand = Ability:Add(385616, true, true)
EchoingReprimand.cooldown_duration = 45
EchoingReprimand.buff_duration = 45
EchoingReprimand.energy_cost = 10
EchoingReprimand[2] = Ability:Add(323558, true, true)
EchoingReprimand[3] = Ability:Add(323559, true, true)
EchoingReprimand[4] = Ability:Add(323560, true, true)
EchoingReprimand[5] = Ability:Add(354838, true, true)
local FindWeakness = Ability:Add(91023, false, true, 316220)
FindWeakness.buff_duration = 10
local Gouge = Ability:Add(1776, false, true)
Gouge.buff_duration = 4
Gouge.cooldown_duration = 15
Gouge.energy_cost = 25
local Nightstalker = Ability:Add(14062, false, true)
local ResoundingClarity = Ability:Add(381622, true, true)
local SealFate = Ability:Add(14190, true, true, 14189)
SealFate.talent_node = 90757
local Sepsis = Ability:Add(385408, false, true)
Sepsis.cooldown_duration = 90
Sepsis.buff_duration = 10
Sepsis.energy_cost = 25
Sepsis.tick_interval = 1
Sepsis.buff = Ability:Add(375939, true, true)
Sepsis.buff.buff_duration = 10
local Shiv = Ability:Add(5938, false, true)
Shiv.cooldown_duration = 25
Shiv.energy_cost = 20
local Subterfuge = Ability:Add(108208, true, true, 115192)
Subterfuge.buff_duration = 3
local ThistleTea = Ability:Add(381623, true, true)
ThistleTea.buff_duration = 6
ThistleTea.cooldown_duration = 3
ThistleTea.requires_charge = true
local TightSpender = Ability:Add(381621, true, true)
local Vigor = Ability:Add(14983, false, true)
local Weaponmaster = Ability:Add({193537, 200733}, false, true)
------ Procs

------ Poisons
local AtrophicPoison = Ability:Add(381637, true, true)
AtrophicPoison.buff_duration = 3600
AtrophicPoison.dot = Ability:Add(392388)
AtrophicPoison.dot.buff_duration = 10
local CripplingPoison = Ability:Add(3408, true, true)
CripplingPoison.buff_duration = 3600
CripplingPoison.dot = Ability:Add(3409)
CripplingPoison.dot.buff_duration = 12
local DeadlyPoison = Ability:Add(2823, true, true)
DeadlyPoison.buff_duration = 3600
DeadlyPoison.dot = Ability:Add(2818, false, true)
DeadlyPoison.dot.buff_duration = 12
DeadlyPoison.dot.tick_interval = 2
DeadlyPoison.dot.hasted_ticks = true
DeadlyPoison.dot:TrackAuras()
local InstantPoison = Ability:Add(315584, true, true)
InstantPoison.buff_duration = 3600
local NumbingPoison = Ability:Add(5761, true, true)
NumbingPoison.buff_duration = 3600
NumbingPoison.dot = Ability:Add(5760)
NumbingPoison.dot.buff_duration = 10
local WoundPoison = Ability:Add(8679, true, true)
WoundPoison.buff_duration = 3600
WoundPoison.dot = Ability:Add(8680, false, true)
WoundPoison.dot.buff_duration = 12
WoundPoison.dot:TrackAuras()
---- Assassination
local Envenom = Ability:Add(32645, true, true)
Envenom.buff_duration = 1
Envenom.energy_cost = 25
Envenom.cp_cost = 1
local FanOfKnives = Ability:Add(51723, false, true)
FanOfKnives.energy_cost = 35
FanOfKnives:AutoAoe(true)
local Garrote = Ability:Add(703, false, true)
Garrote.buff_duration = 18
Garrote.cooldown_duration = 15
Garrote.energy_cost = 45
Garrote.tick_interval = 2
Garrote.hasted_ticks = true
Garrote:TrackAuras()
local Mutilate = Ability:Add(1329, false, true)
Mutilate.energy_cost = 55
local SurgeOfToxins = Ability:Add(192425, false, true)
SurgeOfToxins.buff_duration = 5
local Vendetta = Ability:Add(79140, false, true)
Vendetta.buff_duration = 20
Vendetta.cooldown_duration = 120
Vendetta.triggers_gcd = false
local VirulentPoisons = Ability:Add(252277, true, true)
VirulentPoisons.buff_duration = 6
------ Talents
local Anticipation = Ability:Add(114015, false, true)
local DeathFromAbove = Ability:Add(152150, false, true)
DeathFromAbove.cooldown_duration = 20
DeathFromAbove.energy_cost = 25
DeathFromAbove.cp_cost = 1
DeathFromAbove:AutoAoe(true)
local ElaboratePlanning = Ability:Add(193640, false, true, 193641)
ElaboratePlanning.buff_duration = 5
local Exsanguinate = Ability:Add(200806, false, true)
Exsanguinate.cooldown_duration = 45
Exsanguinate.energy_cost = 25
local Hemorrhage = Ability:Add(16511, false, true)
Hemorrhage.buff_duration = 20
Hemorrhage.energy_cost = 30
local MasterPoisoner = Ability:Add(196864, false, true)
local SerratedBoneSpike = Ability:Add(385424, false, true)
SerratedBoneSpike.buff_duration = 600
SerratedBoneSpike.cooldown_duration = 30
SerratedBoneSpike.energy_cost = 15
SerratedBoneSpike.requires_charge = true
local TinyToxicBlade = Ability:Add(381800, true, true)
local ToxicBlade = Ability:Add(245388, false, true, 245389)
ToxicBlade.buff_duration = 9
ToxicBlade.cooldown_duration = 25
ToxicBlade.energy_cost = 20
local VenomRush = Ability:Add(152152, false, true)
------ Procs

---- Outlaw
local AdrenalineRush = Ability:Add(13750, true, true)
AdrenalineRush.buff_duration = 20
AdrenalineRush.cooldown_duration = 180
local BetweenTheEyes = Ability:Add(315341, true, true)
BetweenTheEyes.buff_duration = 3
BetweenTheEyes.cooldown_duration = 45
BetweenTheEyes.energy_cost = 25
BetweenTheEyes.cp_cost = 1
local BladeFlurry = Ability:Add(13877, true, true)
BladeFlurry.cooldown_duration = 30
BladeFlurry.buff_duration = 12
BladeFlurry.cleave = Ability:Add(22482, false, true)
BladeFlurry.cleave:AutoAoe()
local Dispatch = Ability:Add(2098, false, true)
Dispatch.energy_cost = 35
Dispatch.cp_cost = 1
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
local Broadside = Ability:Add(193356, true, true) -- Roll the Bones
Broadside.buff_duration = 30
local BuriedTreasure = Ability:Add(199600, true, true) -- Roll the Bones
BuriedTreasure.buff_duration = 30
local GrandMelee = Ability:Add(193358, true, true) -- Roll the Bones
GrandMelee.buff_duration = 30
local Opportunity = Ability:Add(279876, true, true, 195627)
Opportunity.buff_duration = 10
local RuthlessPrecision = Ability:Add(193357, true, true) -- Roll the Bones
RuthlessPrecision.buff_duration = 30
local SkullAndCrossbones = Ability:Add(199603, true, true) -- Roll the Bones
SkullAndCrossbones.buff_duration = 30
local TrueBearing = Ability:Add(193359, true, true) -- Roll the Bones
TrueBearing.buff_duration = 30
RollTheBones.buffs = {
	[Broadside] = true,
	[BuriedTreasure] = true,
	[GrandMelee] = true,
	[RuthlessPrecision] = true,
	[SkullAndCrossbones] = true,
	[TrueBearing] = true,
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
------ Talents
local BlackPowder = Ability:Add(319175, false, true)
BlackPowder.energy_cost = 35
BlackPowder.cp_cost = 1
BlackPowder:AutoAoe(true)
local DanseMacabre = Ability:Add(382528, true, true, 393969)
local Gloomblade = Ability:Add(200758, false, true)
Gloomblade.energy_cost = 35
local DarkBrew = Ability:Add(382504, false, true)
local DarkShadow = Ability:Add(245687, false, true)
DarkShadow.talent_node = 90732
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
Flagellation.buff = Ability:Add(384631, true, true)
Flagellation.buff_duration = 12
Flagellation.persist = Ability:Add(394758, true, true)
Flagellation.persist.buff_duration = 12
local ImprovedShurikenStorm = Ability:Add(319951, true, true)
local InvigoratingShadowdust = Ability:Add(382523, true, true)
InvigoratingShadowdust.talent_node = 90706
local LingeringShadow = Ability:Add(382524, true, true, 385960)
LingeringShadow.buff_duration = 18
LingeringShadow.talent_node = 90731
local MasterOfShadows = Ability:Add(196976, true, true, 196980)
MasterOfShadows.buff_duration = 3
local PerforatedVeins = Ability:Add(382518, true, true, 394254)
PerforatedVeins.buff_duration = 20
PerforatedVeins.talent_node = 90707
local Premeditation = Ability:Add(343160, true, true, 343173)
local SecretStratagem = Ability:Add(394320, true, true)
local SecretTechnique = Ability:Add(280719, true, true)
SecretTechnique.cooldown_duration = 60
SecretTechnique.energy_cost = 30
SecretTechnique.cp_cost = 1
SecretTechnique:AutoAoe(true)
local ShadowBlades = Ability:Add(121471, true, true)
ShadowBlades.buff_duration = 20
ShadowBlades.cooldown_duration = 120
local ShadowFocus = Ability:Add(108209, false, true)
local ShotInTheDark = Ability:Add(257505, true, true, 257506)
local ShurikenTornado = Ability:Add(277925, true, true)
ShurikenTornado.energy_cost = 60
ShurikenTornado.buff_duration = 4
ShurikenTornado.cooldown_duration = 60
ShurikenTornado.tick_interval = 1
ShurikenTornado:AutoAoe(true)
local SilentStorm = Ability:Add(385722, true, true, 385727)
local TheRotten = Ability:Add(382015, true, true, 394203)
TheRotten.buff_duration = 30
-- Tier bonuses

-- PvP talents

-- Racials
local ArcaneTorrent = Ability:Add(25046, true, false) -- Blood Elf
local Shadowmeld = Ability:Add(58984, true, true) -- Night Elf
-- Trinket effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
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
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
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

-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.BeaconToTheBeyond = InventoryItem:Add(203963)
Trinket.BeaconToTheBeyond.cooldown_duration = 150
Trinket.DragonfireBombDispenser = InventoryItem:Add(202610)
Trinket.ElementiumPocketAnvil = InventoryItem:Add(202617)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
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
				self.trackAuras[#self.trackAuras + 1] = ability
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
	if EchoingReprimand.known and self.combo_points.anima_charged[self.combo_points.current] then
		return 7
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
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 381301 or -- Feral Hide Drums (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
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
	if not Opt.last_poison.lethal then
		if DeadlyPoison.known then
			Opt.last_poison.lethal = DeadlyPoison.spellId
		elseif InstantPoison.known then
			Opt.last_poison.lethal = InstantPoison.spellId
		elseif WoundPoison.known then
			Opt.last_poison.lethal = WoundPoison.spellId
		end
	end
	if not Opt.last_poison.nonlethal then
		if AtrophicPoison.known then
			Opt.last_poison.nonlethal = AtrophicPoison.spellId
		elseif CripplingPoison.known then
			Opt.last_poison.nonlethal = CripplingPoison.spellId
		elseif NumbingPoison.known then
			Opt.last_poison.nonlethal = NumbingPoison.spellId
		end
	end
	if Opt.last_poison.lethal then
		self.poison.lethal = Abilities.bySpellId[Opt.last_poison.lethal]
	end
	if Opt.last_poison.nonlethal then
		self.poison.nonlethal = Abilities.bySpellId[Opt.last_poison.nonlethal]
	end
end

function Player:UpdateKnown()
	self.combo_points.max = UnitPowerMax('player', 4)

	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
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
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	Sepsis.buff.known = Sepsis.known
	Broadside.known = RollTheBones.known
	BuriedTreasure.known = RollTheBones.known
	GrandMelee.known = RollTheBones.known
	RuthlessPrecision.known = RollTheBones.known
	SkullAndCrossbones.known = RollTheBones.known
	TrueBearing.known = RollTheBones.known
	BladeFlurry.cleave.known = BladeFlurry.known
	EchoingReprimand[2].known = EchoingReprimand.known
	EchoingReprimand[3].known = EchoingReprimand.known
	EchoingReprimand[4].known = EchoingReprimand.known
	EchoingReprimand[5].known = EchoingReprimand.known
	if Gloomblade.known then
		Backstab.known = false
	end
	ShadowTechniques.auto_count = 0

	self.combo_points.max_spend = 5 + (DeeperStratagem.known and 1 or 0) + (DeviousStratagem.known and 1 or 0) + (SecretStratagem.known and 1 or 0)
	self:UpdatePoisons()

	Abilities:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
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
	local _, start, ends, duration, spellId, speed_mh, speed_oh
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.pool_energy = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
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
	self.execute_remains = max(self.cast.ends - self.ctime, self.gcd_remains)
	self.energy.regen = GetPowerRegenForPowerType(3)
	self.energy.max = UnitPowerMax('player', 3)
	self.energy.current = UnitPower('player', 3) + (self.energy.regen * self.execute_remains)
	self.energy.current = clamp(self.energy.current, 0, self.energy.max)
	self.energy.deficit = self.energy.max - self.energy.current
	for i = 2, 5 do
		self.combo_points.anima_charged[i] = EchoingReprimand.known and EchoingReprimand[i]:Up()
	end
	self.combo_points.effective = self:ComboPoints()
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	self.moving = GetUnitSpeed('player') ~= 0
	self.stealth_remains = max(ShadowDance.known and ShadowDance:Remains() or 0, (Subterfuge.known or UnderHandedUpperhand.known) and Subterfuge:Remains() or 0, Sepsis.known and Sepsis.buff:Remains() or 0)
	self.stealthed_nomeld = self.stealth_remains > 0 or Stealth:Up() or Vanish:Up()
	self.stealthed = self.stealthed_nomeld or (Shadowmeld.known and Shadowmeld:Up())
	self:UpdateThreat()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.danse_stacks = DanseMacabre.known and DanseMacabre:Stack() or 0

	self.main = APL[self.spec]:Main()
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	assassinPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
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
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
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
		self:UpdateHealth(true)
	end
	self.boss = false
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
	if CheapShot:Up() or KidneyShot:Up() then
		return true
	end
	return false
end

-- End Target Functions

-- Start Ability Modifications

function Ability:EnergyCost()
	local cost = self.energy_cost
	if ShadowFocus.known and Player.stealthed then
		cost = cost - (cost * 0.15)
	end
	if TightSpender.known and self.cp_cost > 0 then
		cost = cost - (cost * 0.10)
	end
	return cost
end

function Ambush:Usable(...)
	if not (
		Player.stealthed or
		(Audacity.known and Audacity:Up()) or
		(Sepsis.known and Sepsis.buff:Up())
	) then
		return false
	end
	return Ability.Usable(self, ...)
end

function Shadowstrike:Usable()
	if not Player.stealthed then
		return false
	end
	return Ability.Usable(self)
end

function CheapShot:EnergyCost()
	if DirtyTricks.known then
		return 0
	end
	return Ability.EnergyCost(self)
end
Gouge.EnergyCost = CheapShot.EnergyCost

function CheapShot:Usable(...)
	if not Target.stunnable then
		return false
	end
	if not Player.stealthed then
		return false
	end
	return Ability.Usable(self, ...)
end

function Gouge:Usable(...)
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self, ...)
end
KidneyShot.Usable = Gouge.Usable

function DanseMacabre:UsedFor(ability)
	return Player.danse_stacks >= 1 and ability.last_used >= self.last_gained
end

function BetweenTheEyes:Duration()
	return self.buff_duration + (3 * Player.combo_points.current)
end

function BetweenTheEyes:Free()
	return Crackshot.known and Player.stealthed_nomeld
end

function Envenom:Duration()
	return self.buff_duration + Player.combo_points.current
end

function Rupture:Duration()
	return self.buff_duration + (4 * Player.combo_points.current)
end

function SliceAndDice:Duration()
	return self.buff_duration + (6 * Player.combo_points.current)
end

function Opportunity:MaxStack()
	return 1 + (FanTheHammer.known and 5 or 0)
end

function Vanish:Usable(...)
	if Player.stealthed or (not Opt.vanish_solo and Player.group_size == 1) then
		return false
	end
	return Ability.Usable(self, ...)
end
Shadowmeld.Usable = Vanish.Usable

function Stealth:Usable(...)
	if (
		Player:TimeInCombat() > 0 or
		self:Up() or
		Vanish:Up() or
		(ShadowDance.known and ShadowDance:Up())
	) then
		return false
	end
	return Ability.Usable(self, ...)
end

function ShadowDance:Usable(...)
	if Player.stealthed then
		return false
	end
	return Ability.Usable(self, ...)
end

local function TickingPoisoned(self)
	local count, guid, aura, poisoned = 0
	for guid, aura in next, self.aura_targets do
		if aura.expires - Player.time > Player.execute_remains then
			poisoned = DeadlyPoison.dot.aura_targets[guid] or WoundPoison.dot.aura_targets[guid]
			if poisoned then
				if poisoned.expires - Player.time > Player.execute_remains then
					count = count + 1
				end
			end
		end
	end
	return count
end

Garrote.TickingPoisoned = TickingPoisoned
Rupture.TickingPoisoned = TickingPoisoned

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

EchoingReprimand.finishers = {
	[BetweenTheEyes] = true,
	[BlackPowder] = true,
	[DeathFromAbove] = true,
	[Dispatch] = true,
	[Envenom] = true,
	[Eviscerate] = true,
	[Rupture] = true,
	[SecretTechnique] = true,
}

function EchoingReprimand:Remains()
	local remains
	for i = 2, 5 do
		remains = self[i]:Remains()
		if remains > 0 then
			return remains
		end
	end
	return 0
end

EchoingReprimand[2].Remains = function(self)
	if self.consumed then
		return 0 -- BUG: the buff remains for a second or so after it is consumed
	end
	return Ability.Remains(self)
end
EchoingReprimand[3].Remains = EchoingReprimand[2].Remains
EchoingReprimand[4].Remains = EchoingReprimand[2].Remains
EchoingReprimand[5].Remains = EchoingReprimand[2].Remains

Broadside.Remains = function(self, rtbOnly)
	if rtbOnly and self.trigger ~= RollTheBones then
		return 0
	end
	return Ability.Remains(self)
end
BuriedTreasure.Remains = Broadside.Remains
GrandMelee.Remains = Broadside.Remains
RuthlessPrecision.Remains = Broadside.Remains
SkullAndCrossbones.Remains = Broadside.Remains
TrueBearing.Remains = Broadside.Remains

function RollTheBones:Stack(rtbOnly)
	local count, buff = 0
	for buff in next, self.buffs do
		count = count + (buff:Up(rtbOnly) and 1 or 0)
	end
	return count
end

function RollTheBones:Remains(rtbOnly)
	local remains, max, buff = 0, 0
	for buff in next, self.buffs do
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
		if Player.set_bonus.t31 >= 4 then
			count = count - 1
		end
		return max(0, count)
	end
	if buff:Down() or (Player.set_bonus.t31 >= 4 and count <= 1) then
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

function InstantPoison:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Opt.last_poison.lethal = self.spellId
	Player.poison.lethal = self
end
WoundPoison.CastSuccess = InstantPoison.CastSuccess
DeadlyPoison.CastSuccess = InstantPoison.CastSuccess

function AtrophicPoison:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Opt.last_poison.nonlethal = self.spellId
	Player.poison.nonlethal = self
end
CripplingPoison.CastSuccess = AtrophicPoison.CastSuccess
NumbingPoison.CastSuccess = AtrophicPoison.CastSuccess

function Vanish:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Player.stealth_time = Player.time
end
Shadowmeld.CastSuccess = Vanish.CastSuccess

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
	if Player:TimeInCombat() == 0 then
		if Opt.poisons then
			if Player.poison.lethal and Player.poison.lethal:Usable() and Player.poison.lethal:Remains() < 300 then
				return Player.poison.lethal
			end
			if Player.poison.nonlethal and Player.poison.nonlethal:Usable() and Player.poison.nonlethal:Remains() < 300 then
				return Player.poison.nonlethal
			end
		end
		if not Player:InArenaOrBattleground() then
		end
		if not Player.stealthed_nomeld then
			return Stealth
		end
	else

	end
	Player.energy_regen_combined = Player.energy.regen + (Garrote:TickingPoisoned() + Rupture:TickingPoisoned()) * (VenomRush.known and 10 or 7) / 2
	Player.energy_time_to_max_combined = Player.energy.deficit / Player.energy_regen_combined
	local apl
	if Player:TimeInCombat() > 0 then
		apl = self:cds()
		if apl then return apl end
	end
	if Player.enemies > 2 then
		return self:aoe()
	end
	if Player.stealthed then
		return self:stealthed()
	end
	apl = self:maintain()
	if apl then return apl end
	if not Exsanguinate.known or Exsanguinate:Cooldown() > 2 then
		apl = self:finish()
		if apl then return apl end
	end
	if Player.combo_points.deficit > (Anticipation.known and 2 or 1) or Player.energy.deficit <= 25 + Player.energy_regen_combined then
		apl = self:build()
		if apl then return apl end
	end
end

APL[SPEC.ASSASSINATION].aoe = function(self)
--[[
actions.aoe=envenom,if=!buff.envenom.up&combo_points>=cp_max_spend
actions.aoe+=/rupture,cycle_targets=1,if=combo_points>=cp_max_spend&refreshable&(pmultiplier<=1|remains<=tick_time)&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>4
actions.aoe+=/garrote,cycle_targets=1,if=talent.subterfuge.enabled&stealthed.rogue&refreshable&!exsanguinated
actions.aoe+=/envenom,if=combo_points>=cp_max_spend
actions.aoe+=/fan_of_knives
]]
	if Envenom:Usable() and Envenom:Down() and Player.combo_points.effective >= Player.combo_points.max_spend then
		return Envenom
	end
	if Rupture:Usable() and Player.combo_points.effective >= Player.combo_points.max_spend and Rupture:Refreshable() and Target.timeToDie - Rupture:Remains() > 4 then
		return Rupture
	end
	if Subterfuge.known and Garrote:Usable() and Player.stealthed and Garrote:Refreshable() then
		return Garrote
	end
	if Envenom:Usable() and Player.combo_points.effective >= Player.combo_points.max_spend then
		return Envenom
	end
	return FanOfKnives
end

APL[SPEC.ASSASSINATION].build = function(self)
--[[
actions.build=hemorrhage,if=refreshable
actions.build+=/hemorrhage,cycle_targets=1,if=refreshable&dot.rupture.ticking&spell_targets.fan_of_knives<2+equipped.insignia_of_ravenholdt
actions.build+=/fan_of_knives,if=buff.the_dreadlords_deceit.stack>=29
# Mutilate is worth using over FoK for Exsanguinate builds in some 2T scenarios.
actions.build+=/mutilate,if=talent.exsanguinate.enabled&(debuff.vendetta.up|combo_points<=2)
actions.build+=/fan_of_knives,if=spell_targets>1+equipped.insignia_of_ravenholdt
actions.build+=/fan_of_knives,if=combo_points>=3+talent.deeper_stratagem.enabled&artifact.poison_knives.rank>=5|fok_rotation
actions.build+=/mutilate,cycle_targets=1,if=dot.deadly_poison_dot.refreshable
actions.build+=/mutilate
]]
end

APL[SPEC.ASSASSINATION].cds = function(self)
	if ArcaneTorrent:Usable() and Envenom:Down() and Player.energy.deficit >= 15 + Player.energy_regen_combined * Player.gcd_remains * 1.1 then
		return UseCooldown(ArcaneTorrent)
	end
	if Vendetta:Usable() and (not Exsanguinate.known or Rupture:Up()) then
		return UseCooldown(Vendetta)
	end
	if Vanish:Usable() and not Player.stealthed then
		if Target.timeToDie <= 6 then
			return UseCooldown(Vanish)
		end
		if Nightstalker.known then
			if Player.combo_points.effective >= Player.combo_points.max_spend then
				if not Exsanguinate.known and Vendetta:Up() then
					return UseCooldown(Vanish)
				elseif Exsanguinate.known and Exsanguinate:Ready(1) then
					return UseCooldown(Vanish)
				end
			end
		elseif Subterfuge.known then
			if Garrote:Refreshable() and ((Player.enemies <= 3 and Player.combo_points.deficit >= 1 + Player.enemies) or (Player.enemies >= 4 and Player.combo_points.deficit >= 4)) then
				return UseCooldown(Vanish)
			end
		elseif ShadowFocus.known and Player.energy_time_to_max_combined >= 2 and Player.combo_points.deficit >= 4 then
			return UseCooldown(Vanish)
		end
	end
	if ToxicBlade:Usable() and (Target.timeToDie <= 6 or Player.combo_points.deficit >= 1 and Rupture:Remains() > 8 and Vendetta:Cooldown() > 10) then
		return UseCooldown(ToxicBlade)
	end
end

APL[SPEC.ASSASSINATION].finish = function(self)
--[[
actions.finish=death_from_above,if=combo_points>=5
actions.finish+=/envenom,if=talent.anticipation.enabled&combo_points>=5&((debuff.toxic_blade.up&buff.virulent_poisons.remains<2)|mantle_duration>=0.2|buff.virulent_poisons.remains<0.2|energy.deficit<=25+variable.energy_regen_combined)
actions.finish+=/envenom,if=talent.anticipation.enabled&combo_points>=4&!buff.virulent_poisons.up
actions.finish+=/envenom,if=!talent.anticipation.enabled&combo_points>=4+(talent.deeper_stratagem.enabled&!set_bonus.tier19_4pc)&(debuff.vendetta.up|debuff.toxic_blade.up|mantle_duration>=0.2|debuff.surge_of_toxins.remains<0.2|energy.deficit<=25+variable.energy_regen_combined)
actions.finish+=/envenom,if=talent.elaborate_planning.enabled&combo_points>=3+!talent.exsanguinate.enabled&buff.elaborate_planning.remains<0.2
]]
end

APL[SPEC.ASSASSINATION].maintain = function(self)
--[[
actions.maintain=rupture,if=talent.exsanguinate.enabled&((combo_points>=cp_max_spend&cooldown.exsanguinate.remains<1)|(!ticking&(time>10|combo_points>=2+artifact.urge_to_kill.enabled)))
actions.maintain+=/rupture,cycle_targets=1,if=combo_points>=4&refreshable&(pmultiplier<=1|remains<=tick_time)&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>6
actions.maintain+=/pool_resource,for_next=1
actions.maintain+=/garrote,cycle_targets=1,if=(!talent.subterfuge.enabled|!(cooldown.vanish.up&cooldown.vendetta.remains<=4))&combo_points.deficit>=1&refreshable&(pmultiplier<=1|remains<=tick_time)&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>4
actions.maintain+=/garrote,if=set_bonus.tier20_4pc&talent.exsanguinate.enabled&prev_gcd.1.rupture&cooldown.exsanguinate.remains<1&(!cooldown.vanish.up|time>12)
actions.maintain+=/garrote,if=!set_bonus.tier20_4pc&talent.exsanguinate.enabled&cooldown.exsanguinate.remains<2+2*(cooldown.vanish.remains<2)&time>12
actions.maintain+=/rupture,if=!talent.exsanguinate.enabled&combo_points>=3&!ticking&mantle_duration=0&target.time_to_die>6
]]
end

APL[SPEC.ASSASSINATION].stealthed = function(self)
--[[
actions.stealthed=mutilate,if=talent.shadow_focus.enabled&dot.garrote.ticking
actions.stealthed+=/garrote,cycle_targets=1,if=talent.subterfuge.enabled&combo_points.deficit>=1&set_bonus.tier20_4pc&((dot.garrote.remains<=13&!debuff.toxic_blade.up)|pmultiplier<=1)&!exsanguinated
actions.stealthed+=/garrote,cycle_targets=1,if=talent.subterfuge.enabled&combo_points.deficit>=1&!set_bonus.tier20_4pc&refreshable&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>2
actions.stealthed+=/garrote,cycle_targets=1,if=talent.subterfuge.enabled&combo_points.deficit>=1&!set_bonus.tier20_4pc&remains<=10&pmultiplier<=1&!exsanguinated&target.time_to_die-remains>2
actions.stealthed+=/rupture,cycle_targets=1,if=combo_points>=4&refreshable&(pmultiplier<=1|remains<=tick_time)&(!exsanguinated|remains<=tick_time*2)&target.time_to_die-remains>6
actions.stealthed+=/rupture,if=talent.exsanguinate.enabled&talent.nightstalker.enabled&target.time_to_die-remains>6
actions.stealthed+=/envenom,if=combo_points>=cp_max_spend
actions.stealthed+=/garrote,if=!talent.subterfuge.enabled&target.time_to_die-remains>4
actions.stealthed+=/mutilate
]]
	if ShadowFocus.known and Mutilate:Usable() and Garrote:Ticking() > 0 then
		return Mutilate
	end
	if Subterfuge.known and Garrote:Usable() and Player.combo_points.deficit >= 1 and Garrote:Refreshable() and Garrote:Remains() <= Garrote:TickTime() * 2 and Target.timeToDie - Garrote:Remains() > 2 then
		return Garrote
	end
	if Rupture:Usable() then
		if Rupture:Refreshable() and Player.combo_points.effective >= 4 and Rupture:Remains() <= Rupture:TickTime() and Target.timeToDie - Rupture:Remains() > 6 then
			return Rupture
		end
		if Exsanguinate.known and Nightstalker.known and Target.timeToDie - Rupture:Remains() > 6 then
			return Rupture
		end
	end
	if Envenom:Usable() and Player.combo_points.effective >= Player.combo_points.max_spend then
		return Envenom
	end
	if not Subterfuge.known and Garrote:Usable() and Target.timeToDie - Garrote:Remains() > 4 then
		return Garrote
	end
	if Mutilate:Usable() then
		return Mutilate
	end
end

APL[SPEC.OUTLAW].Main = function(self)
	self.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or AdrenalineRush:Up())
	self:rtb()

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
			if Player.poison.lethal and Player.poison.lethal:Usable() and Player.poison.lethal:Remains() < 300 then
				return Player.poison.lethal
			end
			if Player.poison.nonlethal and Player.poison.nonlethal:Usable() and Player.poison.nonlethal:Remains() < 300 then
				return Player.poison.nonlethal
			end
		end
		if self.use_cds and UnderhandedUpperHand.known and BladeFlurry:Usable() and AdrenalineRush:Ready() and BladeFlurry:Down() then
			UseCooldown(BladeFlurry)
		end
		if RollTheBones:Usable() and (self.rtb_reroll or self.rtb_remains < 5 or (self.rtb_buffs == 1 and Player.set_bonus.t31 >= 4)) then
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
		if Shadowmeld.known and Stealth:Usable() and Shadowmeld:Up() then
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
	self.ambush_condition = Player.energy.current >= 50 and (HiddenOpportunity.known or Player.combo_points.deficit >= (2 + (ImprovedAmbush.known and 1 or 0) + (Broadside:Up() and 1 or 0)))
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
# Default Roll the Bones reroll rule: reroll for any buffs that aren't Buried Treasure, excluding Grand Melee in single target
actions+=/variable,name=rtb_reroll,value=rtb_buffs.will_lose=(rtb_buffs.will_lose.buried_treasure+rtb_buffs.will_lose.grand_melee&spell_targets.blade_flurry<2&raid_event.adds.in>10)
# Crackshot builds without T31 should reroll for True Bearing (or Broadside without Hidden Opportunity) if we won't lose over 1 buff
actions+=/variable,name=rtb_reroll,if=talent.crackshot&!set_bonus.tier31_4pc,value=(!rtb_buffs.will_lose.true_bearing&talent.hidden_opportunity|!rtb_buffs.will_lose.broadside&!talent.hidden_opportunity)&rtb_buffs.will_lose<=1
# Crackshot builds with T31 should reroll if we won't lose over 1 buff (2 with Loaded Dice)
actions+=/variable,name=rtb_reroll,if=talent.crackshot&set_bonus.tier31_4pc,value=(rtb_buffs.will_lose<=1+buff.loaded_dice.up)
# Hidden Opportunity builds without Crackshot should reroll for Skull and Crossbones or any 2 buffs excluding Grand Melee in single target
actions+=/variable,name=rtb_reroll,if=!talent.crackshot&talent.hidden_opportunity,value=!rtb_buffs.will_lose.skull_and_crossbones&(rtb_buffs.will_lose<2+rtb_buffs.will_lose.grand_melee&spell_targets.blade_flurry<2&raid_event.adds.in>10)
# Additional reroll rules if all active buffs will not be rolled away and we don't already have 5+ buffs outside of stealth
actions+=/variable,name=rtb_reroll,value=variable.rtb_reroll&rtb_buffs.longer=0|rtb_buffs.normal=0&rtb_buffs.longer>=1&rtb_buffs<5&rtb_buffs.max_remains<=39&!stealthed.all
# Avoid rerolls when we will not have time remaining on the fight or add wave to recoup the opportunity cost of the global
actions+=/variable,name=rtb_reroll,op=reset,if=!(raid_event.adds.remains>12|raid_event.adds.up&(raid_event.adds.in-raid_event.adds.remains)<6|target.time_to_die>12)|fight_remains<12
]]
	self.rtb_remains = RollTheBones:Remains()
	self.rtb_buffs = RollTheBones:Stack()
	self.rtb_will_lose = RollTheBones:WillLose()
	if Target.boss and Target.timeToDie < 12 then
		self.rtb_reroll = false
	elseif Crackshot.known then
		if Player.set_bonus.t31 >= 4 then
			self.rtb_reroll = self.rtb_will_lose <= (1 + (LoadedDice:Up() and 1 or 0))
		else
			self.rtb_reroll = self.rtb_will_lose <= 1 and ((HiddenOpportunity.known and not RollTheBones:WillLose(TrueBearing)) or (not HiddenOpportunity.known and not RollTheBones:WillLose(Broadside)))
		end
	elseif HiddenOpportunity.known then
		self.rtb_reroll = not RollTheBones:WillLose(SkullAndCrossbones) and self.rtb_will_lose < (2 + ((Player.enemies < 2 and RollTheBones:WillLose(GrandMelee)) and 1 or 0))
	else
		self.rtb_reroll = self.rtb_will_lose == ((RollTheBones:WillLose(BuriedTreasure) and 1 or 0) + ((Player.enemies < 2 and RollTheBones:WillLose(GrandMelee)) and 1 or 0))
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
		if Crackshot.known and BetweenTheEyes:Usable(0, true) and Shadowmeld:Down() then
			return Pool(BetweenTheEyes)
		end
		if Dispatch:Usable() then
			return Dispatch
		end
	end
	if Crackshot.known and PistolShot:Usable() and FanTheHammer.rank >= 2 and Opportunity:Stack() >= 6 and ((Broadside:Up() and Player.combo_points.current <= 1) or GreenskinsWickers:Up()) then
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
	if self.vanish_condition and Shadowmeld:Usable() and self.finish_condition and not Vanish:Ready() and not ShadowDance:Ready() then
		return UseCooldown(Shadowmeld)
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
# Use Roll the Bones if reroll conditions are met, or with no buffs, or 2s before buffs expire with T31, or 7s before buffs expire with Vanish/Dance ready
#actions.cds+=/roll_the_bones,if=rtb_buffs=0|rtb_buffs.max_remains<=2&set_bonus.tier31_4pc|(!talent.crackshot|buff.subterfuge.down)&(variable.rtb_reroll|rtb_buffs.max_remains<=7&(cooldown.shadow_dance.ready|cooldown.vanish.ready))
# Use Keep it Rolling with at least 3 buffs (4 with T31)
actions.cds+=/keep_it_rolling,if=!variable.rtb_reroll&rtb_buffs>=3+set_bonus.tier31_4pc&(buff.shadow_dance.down|rtb_buffs>=6)
actions.cds+=/ghostly_strike
# Use Sepsis to trigger Crackshot or if the target will survive its DoT
actions.cds+=/sepsis,if=talent.crackshot&cooldown.between_the_eyes.ready&variable.finish_condition&!stealthed.all|!talent.crackshot&target.time_to_die>11&buff.between_the_eyes.up|fight_remains<11
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
actions.cds+=/use_item,name=manic_grieftorch,use_off_gcd=1,if=gcd.remains>gcd.max-0.1&!stealthed.all&buff.between_the_eyes.up|fight_remains<=5
actions.cds+=/use_item,name=dragonfire_bomb_dispenser,use_off_gcd=1,if=(!trinket.1.is.dragonfire_bomb_dispenser&trinket.1.cooldown.remains>10|trinket.2.cooldown.remains>10)|cooldown.dragonfire_bomb_dispenser.charges>2|fight_remains<20|!trinket.2.has_cooldown|!trinket.1.has_cooldown
actions.cds+=/use_item,name=beacon_to_the_beyond,use_off_gcd=1,if=gcd.remains>gcd.max-0.1&!stealthed.all&buff.between_the_eyes.up|fight_remains<=5
actions.cds+=/use_item,name=stormeaters_boon,if=spell_targets.blade_flurry>desired_targets|raid_event.adds.in>60|fight_remains<10
actions.cds+=/use_item,name=windscar_whetstone,if=spell_targets.blade_flurry>desired_targets|raid_event.adds.in>60|fight_remains<7
actions.cds+=/use_items,slots=trinket1,if=buff.between_the_eyes.up|trinket.1.has_stat.any_dps|fight_remains<=20
actions.cds+=/use_items,slots=trinket2,if=buff.between_the_eyes.up|trinket.2.has_stat.any_dps|fight_remains<=20
]]
	if self.use_cds and AdrenalineRush:Usable() and (AdrenalineRush:Down() or (Player.stealthed and Crackshot.known and ImprovedAdrenalineRush.known)) and (Player.combo_points.current <= 2 or not ImprovedAdrenalineRush.known) then
		return UseCooldown(AdrenalineRush)
	end
	if BladeFlurry:Usable() and (
		(Player.enemies >= (2 - (UnderhandedUpperHand.known and 1 or 0)) and not Player.stealthed and BladeFlurry:Remains() < Player.gcd) or
		(DeftManeuvers.known and not self.finish_condition and (Player.enemies >= 5 or (Player.enemies >= 3 and Player.combo_points.deficit == (Player.enemies + (Broadside:Up() and 1 or 0)))))
	) then
		return UseCooldown(BladeFlurry)
	end
	if RollTheBones:Usable() and (
		self.rtb_buffs == 0 or
		(self.rtb_remains <= 2 and Player.set_bonus.t31 >= 4) or
		((not Crackshot.known or Subterfuge:Down()) and (
			self.rtb_reroll or
			(self.rtb_remains <= 7 and (ShadowDance:Ready() or (self.vanish_condition and Vanish:Ready())))
		))
	) then
		return UseCooldown(RollTheBones)
	end
	if self.use_cds and KeepItRolling:Usable() and not self.rtb_reroll and self.rtb_buffs >= (3 + (Player.set_bonus.t31 >= 4 and 1 or 0)) and (ShadowDance:Down() or self.rtb_buffs >= 6) then
		return UseCooldown(KeepItRolling)
	end
	if self.use_cds and GhostlyStrike:Usable() then
		return UseCooldown(GhostlyStrike)
	end
	if self.use_cds and Sepsis:Usable() and (
		(Crackshot.known and BetweenTheEyes:Ready() and self.finish_condition and not Player.stealthed) or
		(not Crackshot.known and Target.timeToDie > 11 and BetweenTheEyes:Up()) or
		(Target.boss and Target.timeToDie < 11)
	) then
		return UseCooldown(Sepsis)
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
		if Trinket.BeaconToTheBeyond:Usable() and not Player.stealthed and BetweenTheEyes:Up() then
			return UseCooldown(Trinket.BeaconToTheBeyond)
		elseif Trinket.DragonfireBombDispenser:Usable() and (Player.enemies > 1 or Target.timeToDie > 8) then
			return UseCooldown(Trinket.DragonfireBombDispenser)
		elseif Trinket.ElementiumPocketAnvil:Usable() and Player.energy.deficit >= (15 + Player.energy.regen) and not Player.stealthed then
			return UseCooldown(Trinket.ElementiumPocketAnvil)
		elseif (Target.boss and Target.timeToDie < 20) or (BetweenTheEyes:Up() and (not GhostlyStrike.known or GhostlyStrike:Up())) then
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
# Finishers  Use Between the Eyes to keep the crit buff up, but on cooldown if Improved/Greenskins/T30, and avoid overriding Greenskins
actions.finish=between_the_eyes,if=!talent.crackshot&(buff.between_the_eyes.remains<4|talent.improved_between_the_eyes|talent.greenskins_wickers|set_bonus.tier30_4pc)&!buff.greenskins_wickers.up
# Crackshot builds use Between the Eyes outside of Stealth if Vanish or Dance will not come off cooldown within the next cast
actions.finish+=/between_the_eyes,if=talent.crackshot&(cooldown.vanish.remains>45&cooldown.shadow_dance.remains>12)
actions.finish+=/slice_and_dice,if=buff.slice_and_dice.remains<fight_remains&refreshable
actions.finish+=/killing_spree,if=debuff.ghostly_strike.up|!talent.ghostly_strike
actions.finish+=/cold_blood
actions.finish+=/dispatch
]]
	if BetweenTheEyes:Usable(Player:EnergyTimeToMax(50), true) and (
		(not Crackshot.known and (not GreenskinsWickers.known or GreenskinsWickers:Down()) and (BetweenTheEyes:Remains() < 4 or ImprovedBetweenTheEyes.known or GreenskinsWickers.known or Player.set_bonus.t30 >= 4)) or
		(Crackshot.known and ((not self.vanish_condition or not Vanish:Ready(45)) and not ShadowDance:Ready(12)))
	) then
		return Pool(BetweenTheEyes)
	end
	if SliceAndDice:Usable(0, true) and SliceAndDice:Refreshable() and (Player.enemies > 1 or SliceAndDice:Remains() < Target.timeToDie) and (not Player.combo_points.anima_charged[Player.combo_points.current] or SliceAndDice:Down()) and (not SwiftSlasher.known or Player.combo_points.current >= Player.combo_points.max_spend) then
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
	if EchoingReprimand:Usable() then
		return EchoingReprimand
	end
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
				Player.combo_points.deficit <= (1 + (Broadside:Up() and 1 or 0)) or
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
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=apply_poison
actions.precombat+=/flask
actions.precombat+=/augmentation
actions.precombat+=/food
actions.precombat+=/snapshot_stats
actions.precombat+=/stealth
actions.precombat+=/marked_for_death,precombat_seconds=15
actions.precombat+=/variable,name=algethar_puzzle_box_precombat_cast,value=3
actions.precombat+=/use_item,name=algethar_puzzle_box
actions.precombat+=/slice_and_dice,precombat_seconds=1
]]
		if Opt.poisons then
			if Player.poison.lethal and Player.poison.lethal:Usable() and Player.poison.lethal:Remains() < 300 then
				return Player.poison.lethal
			end
			if Player.poison.nonlethal and Player.poison.nonlethal:Usable() and Player.poison.nonlethal:Remains() < 300 then
				return Player.poison.nonlethal
			end
		end
		if not Player:InArenaOrBattleground() then

		end
		if Stealth:Usable() then
			return Stealth
		end
		if SliceAndDice:Usable() and SliceAndDice:Remains() < (4 * Player.combo_points.current) and Player.combo_points.current >= 2 then
			return SliceAndDice
		end
	else

	end
--[[
actions=stealth
actions+=/kick
actions+=/variable,name=snd_condition,value=buff.slice_and_dice.up|spell_targets.shuriken_storm>=cp_max_spend
actions+=/variable,name=is_next_cp_animacharged,if=talent.echoing_reprimand.enabled,value=combo_points=1&buff.echoing_reprimand_2.up|combo_points=2&buff.echoing_reprimand_3.up|combo_points=3&buff.echoing_reprimand_4.up|combo_points=4&buff.echoing_reprimand_5.up
actions+=/variable,name=effective_combo_points,value=effective_combo_points
actions+=/variable,name=effective_combo_points,if=talent.echoing_reprimand.enabled&effective_combo_points>combo_points&combo_points.deficit>2&time_to_sht.4.plus<0.5&!variable.is_next_cp_animacharged,value=combo_points
actions+=/call_action_list,name=cds
actions+=/slice_and_dice,if=spell_targets.shuriken_storm<cp_max_spend&buff.slice_and_dice.remains<gcd.max&fight_remains>6&combo_points>=4
actions+=/run_action_list,name=stealthed,if=stealthed.all
actions+=/variable,name=priority_rotation,value=priority_rotation
actions+=/variable,name=stealth_threshold,value=25+talent.vigor.enabled*20+talent.master_of_shadows.enabled*20+talent.shadow_focus.enabled*25+talent.alacrity.enabled*20+25*(spell_targets.shuriken_storm>=4)
actions+=/call_action_list,name=stealth_cds,if=energy.deficit<=variable.stealth_threshold
actions+=/call_action_list,name=finish,if=variable.effective_combo_points>=cp_max_spend
actions+=/call_action_list,name=finish,if=combo_points.deficit<=1+buff.the_rotten.up|fight_remains<=1&variable.effective_combo_points>=3
actions+=/call_action_list,name=finish,if=spell_targets.shuriken_storm>=(4-talent.seal_fate)&variable.effective_combo_points>=4
actions+=/call_action_list,name=build,if=energy.deficit<=variable.stealth_threshold
actions+=/arcane_torrent,if=energy.deficit>=15+energy.regen
actions+=/arcane_pulse
actions+=/lights_judgment
actions+=/bag_of_tricks
]]
	self.snd_condition = Player.enemies >= Player.combo_points.max_spend or SliceAndDice:Up()
	self.is_next_cp_animacharged = EchoingReprimand.known and Player.combo_points.anima_charged[Player.combo_points.current + 1]
	if EchoingReprimand.known and Player.combo_points.effective > Player.combo_points.current and Player.combo_points.deficit > 2 and ShadowTechniques:TimeTo(4) < 0.5 and not self.is_next_cp_animacharged then
		Player.combo_points.effective = Player.combo_points.current
	end
	self.priority_rotation = Opt.priority_rotation and Player.enemies >= 2
	if Shadowmeld.known and Stealth:Usable() and Shadowmeld:Up() then
		return Stealth
	end
	self:cds()
	if Player.stealthed then
		return self:stealthed()
	end
	self.stealth_threshold = 25 + (Vigor.known and 20 or 0) + (MasterOfShadows.known and 20 or 0) + (ShadowFocus.known and 25 or 0) + (Alacrity.known and 20 or 0) + (Player.enemies >= 4 and 25 or 0)
	if not Player.cd and Player.energy.deficit <= self.stealth_threshold then
		self:stealth_cds()
	end
	local apl
	if (
		Player.combo_points.effective >= Player.combo_points.max_spend or
		Player.combo_points.deficit <= (1 + (TheRotten.known and TheRotten:Up() and 1 or 0)) or
		(Player.combo_points.effective >= 3 and Player.enemies == 1 and Target.timeToDie < 1) or
		(Player.combo_points.effective >= 4 and Player.enemies >= (4 - (SealFate.known and 1 or 0)))
	) then
		apl = self:finish()
		if apl then return apl end
	end
	if Player.energy.deficit <= self.stealth_threshold then
		apl = self:build()
		if apl then return apl end
	end
	if ArcaneTorrent:Usable() and Player.energy.deficit >= (15 + Player.energy.regen) then
		UseCooldown(ArcaneTorrent)
	end
end

APL[SPEC.SUBTLETY].cds = function(self)
--[[
actions.cds=variable,name=rotten_condition,value=!buff.premeditation.up&spell_targets.shuriken_storm=1|!talent.the_rotten|spell_targets.shuriken_storm>1
actions.cds+=/shadow_dance,use_off_gcd=1,if=!buff.shadow_dance.up&buff.shuriken_tornado.up&buff.shuriken_tornado.remains<=3.5
actions.cds+=/symbols_of_death,use_off_gcd=1,if=buff.shuriken_tornado.up&buff.shuriken_tornado.remains<=3.5
actions.cds+=/vanish,if=buff.danse_macabre.stack>3&combo_points<=2&(cooldown.secret_technique.remains>=30|!talent.secret_technique)
actions.cds+=/cold_blood,if=!talent.secret_technique&combo_points>=5
actions.cds+=/flagellation,target_if=max:target.time_to_die,if=variable.snd_condition&combo_points>=5&target.time_to_die>10
actions.cds+=/pool_resource,for_next=1,if=talent.shuriken_tornado.enabled&!talent.shadow_focus.enabled
actions.cds+=/shuriken_tornado,if=spell_targets.shuriken_storm<=1&energy>=60&variable.snd_condition&cooldown.symbols_of_death.up&cooldown.shadow_dance.charges>=1&(!talent.flagellation.enabled&!cooldown.flagellation.up|buff.flagellation_buff.up|spell_targets.shuriken_storm>=5)&combo_points<=2&!buff.premeditation.up
actions.cds+=/sepsis,if=variable.snd_condition&combo_points.deficit>=1&target.time_to_die>=16
actions.cds+=/symbols_of_death,if=(buff.symbols_of_death.remains<=3&!cooldown.shadow_dance.ready|!set_bonus.tier30_2pc)&variable.rotten_condition&variable.snd_condition&(!talent.flagellation&(combo_points<=1|!talent.the_rotten)|cooldown.flagellation.remains>10|cooldown.flagellation.up&combo_points>=5)
actions.cds+=/marked_for_death,line_cd=1.5,target_if=min:target.time_to_die,if=raid_event.adds.up&(target.time_to_die<combo_points.deficit|!stealthed.all&combo_points.deficit>=cp_max_spend)
actions.cds+=/marked_for_death,if=raid_event.adds.in>30-raid_event.adds.duration&combo_points.deficit>=cp_max_spend
actions.cds+=/shadow_blades,if=variable.snd_condition&combo_points.deficit>=2&target.time_to_die>=10&(dot.sepsis.ticking|cooldown.sepsis.remains<=8|!talent.sepsis)|fight_remains<=20
actions.cds+=/echoing_reprimand,if=variable.snd_condition&combo_points.deficit>=3&(variable.priority_rotation|spell_targets.shuriken_storm<=4|talent.resounding_clarity)&(buff.shadow_dance.up|!talent.danse_macabre)
actions.cds+=/shuriken_tornado,if=variable.snd_condition&buff.symbols_of_death.up&combo_points<=2&(!buff.premeditation.up|spell_targets.shuriken_storm>4)
actions.cds+=/shuriken_tornado,if=cooldown.shadow_dance.ready&!stealthed.all&spell_targets.shuriken_storm>=3&!talent.flagellation.enabled
actions.cds+=/shadow_dance,if=!buff.shadow_dance.up&fight_remains<=8+talent.subterfuge.enabled
actions.cds+=/thistle_tea,if=(cooldown.symbols_of_death.remains>=3|buff.symbols_of_death.up)&!buff.thistle_tea.up&(energy.deficit>=100&(combo_points.deficit>=2|spell_targets.shuriken_storm>=3)|cooldown.thistle_tea.charges_fractional>=2.75&buff.shadow_dance.up)|buff.shadow_dance.remains>=4&!buff.thistle_tea.up&spell_targets.shuriken_storm>=3|!buff.thistle_tea.up&fight_remains<=(6*cooldown.thistle_tea.charges)
actions.cds+=/potion,if=buff.bloodlust.react|fight_remains<30|buff.symbols_of_death.up&(buff.shadow_blades.up|cooldown.shadow_blades.remains<=10)
actions.cds+=/blood_fury,if=buff.symbols_of_death.up
actions.cds+=/berserking,if=buff.symbols_of_death.up
actions.cds+=/fireblood,if=buff.symbols_of_death.up
actions.cds+=/ancestral_call,if=buff.symbols_of_death.up
actions.cds+=/use_item,name=beacon_to_the_beyond,use_off_gcd=1,if=!stealthed.all&(buff.deeper_daggers.up|!talent.deeper_daggers)&(!raid_event.adds.up|!equipped.stormeaters_boon|trinket.stormeaters_boon.cooldown.remains>20)
actions.cds+=/use_item,name=manic_grieftorch,use_off_gcd=1,if=!stealthed.all&(!raid_event.adds.up|!equipped.stormeaters_boon|trinket.stormeaters_boon.cooldown.remains>20)
actions.cds+=/use_items,if=!stealthed.all|fight_remains<10
]]
	self.rotten_condition = not TheRotten.known or Player.enemies > 1 or Premeditation:Down()
	if ShurikenTornado.known and ShurikenTornado:Up() and ShurikenTornado:Remains() <= 3.5 then
		if ShadowDance:Usable() and ShadowDance:Down() then
			return UseCooldown(ShadowDance)
		end
		if SymbolsOfDeath:Usable() and SymbolsOfDeath:Remains() < 1 and (Player.set_bonus.t30 < 2 or not ShadowDance:Ready(5)) then
			return UseCooldown(SymbolsOfDeath)
		end
	end
	if Vanish:Usable() and Player.danse_stacks > 3 and Player.combo_points.current <= 2 and (not SecretTechnique.known or not SecretTechnique:Ready(30)) then
		return UseCooldown(Vanish)
	end
	if ColdBlood:Usable() and not SecretTechnique.known and Player.combo_points.current >= 5 then
		return UseCooldown(ColdBlood)
	end
	if Flagellation:Usable() and self.snd_condition and Player.combo_points.current >= 5 and Target.timeToDie > 10 then
		return UseCooldown(Flagellation)
	end
	if ShurikenTornado:Usable(0, true) and Player.enemies <= 1 and self.snd_condition and not (Stealth:Up() or Vanish:Up() or Shadowmeld:Up()) and (Player.set_bonus.t30 >= 2 or SymbolsOfDeath:Ready() or SymbolsOfDeath:Remains() > 4) and ShadowDance:Ready() and Player.combo_points.current <= 2 and Premeditation:Down() and (not Flagellation.known or not Flagellation:Ready() or Flagellation.buff:Up()) then
		if not ShadowFocus.known then
			Player.pool_energy = 60
			return UseCooldown(ShurikenTornado)
		end
		if Player.energy.current >= 60 then
			return UseCooldown(ShurikenTornado)
		end
	end
	if Sepsis:Usable() and self.snd_condition and Player.combo_points.deficit >= 1 and Target.timeToDie >= 16 then
		return UseCooldown(Sepsis)
	end
	if SymbolsOfDeath:Usable() and self.rotten_condition and self.snd_condition and (Player.set_bonus.t30 < 2 or (SymbolsOfDeath:Remains() < 1 and not ShadowDance:Ready(SymbolsOfDeath:Remains() + 5))) and ((not Flagellation.known and (Player.combo_points.current <= 1 or not TheRotten.known)) or (Flagellation.known and (not Flagellation:Ready(10) or (Flagellation:Ready() and Player.combo_points.current >= 5)))) then
		return UseCooldown(SymbolsOfDeath)
	end
	if ShadowBlades:Usable() and ShadowBlades:Down() and ((self.snd_condition and Player.combo_points.deficit >= 2 and (Target.timeToDie >= 10 or Player.enemies > 1) and (not Sepsis.known or Sepsis:Ready(8) or Sepsis:Up())) or (Target.boss and Target.timeToDie < 20)) then
		return UseCooldown(ShadowBlades)
	end
	if EchoingReprimand:Usable() and EchoingReprimand:Down() and self.snd_condition and Player.combo_points.deficit >= 3 and (self.priority_rotation or Player.enemies <= 4 or ResoundingClarity.known) and (not DanseMacabre.known or (Player.danse_stacks >= 1 and not DanseMacabre:UsedFor(EchoingReprimand))) then
		return UseCooldown(EchoingReprimand)
	end
	if ShurikenTornado:Usable() and (
		(self.snd_condition and SymbolsOfDeath:Up() and Player.combo_points.current <= 2 and (Premeditation:Down() or Player.enemies > 4)) or
		(not Flagellation.known and ShadowDance:Ready() and not Player:Stealthed() and Player.enemies >= 3)
	) then
		return UseCooldown(ShurikenTornado)
	end
	if ShadowDance:Usable() and Target.boss and Target.timeToDie <= (8 + (Subterfuge.known and 1 or 0)) then
		return UseCooldown(ShadowDance)
	end
	if ThistleTea:Usable() and ThistleTea:Down() and (
		((SymbolsOfDeath:Up() or not SymbolsOfDeath:Ready(3)) and (Player.energy.deficit >= 100 and (Player.combo_points.deficit >= 2 or Player.enemies >= 3) or ThistleTea:ChargesFractional() >= 2.75 and ShadowDance:Up())) or
		(ShadowDance:Remains() >= 4 and Player.enemies >= 3) or
		(Target.boss and Target.timeToDie < (6 * ThistleTea:Charges()))
	) then
		UseExtra(ThistleTea)
	end
	if Opt.trinket and not (Stealth:Up() or Vanish:Up() or Shadowmeld:Up()) then
		if Trinket.BeaconToTheBeyond:Usable() and ShadowDance:Down() and (not DeeperDaggers.known or DeeperDaggers:Up()) then
			return UseCooldown(Trinket.BeaconToTheBeyond)
		elseif Trinket.DragonfireBombDispenser:Usable() and (Player.enemies > 1 or Target.timeToDie > 8) then
			return UseCooldown(Trinket.DragonfireBombDispenser)
		elseif Trinket.ElementiumPocketAnvil:Usable() and Player.energy.deficit >= (15 + Player.energy.regen) and ShadowDance:Down() and ShurikenTornado:Down() then
			return UseCooldown(Trinket.ElementiumPocketAnvil)
		elseif (Target.boss and Target.timeToDie < 20) or SymbolsOfDeath:Remains() > 6 then
			if Trinket1:Usable() then
				return UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				return UseCooldown(Trinket2)
			end
		end
	end
end

APL[SPEC.SUBTLETY].stealth_cds = function(self)
--[[
actions.stealth_cds=variable,name=shd_threshold,value=cooldown.shadow_dance.charges_fractional>=0.75+talent.shadow_dance
actions.stealth_cds+=/variable,name=rotten_threshold,value=!buff.the_rotten.up|spell_targets.shuriken_storm>1|combo_points<=2&buff.the_rotten.up&!set_bonus.tier30_2pc
actions.stealth_cds+=/vanish,if=(!talent.danse_macabre|spell_targets.shuriken_storm>=3)&!variable.shd_threshold&combo_points.deficit>1&(cooldown.flagellation.remains>=60|!talent.flagellation|fight_remains<=(30*cooldown.vanish.charges))
actions.stealth_cds+=/pool_resource,for_next=1,extra_amount=40,if=race.night_elf
actions.stealth_cds+=/shadowmeld,if=energy>=40&energy.deficit>=10&!variable.shd_threshold&combo_points.deficit>4
actions.stealth_cds+=/variable,name=shd_combo_points,value=combo_points<=1
actions.stealth_cds+=/variable,name=shd_combo_points,value=combo_points.deficit<=1,if=spell_targets.shuriken_storm>(4-2*talent.shuriken_tornado.enabled)|variable.priority_rotation&spell_targets.shuriken_storm>=4
actions.stealth_cds+=/variable,name=shd_combo_points,value=1,if=spell_targets.shuriken_storm=(4-talent.seal_fate)
actions.stealth_cds+=/shadow_dance,if=(variable.shd_combo_points&(!talent.shadow_dance&buff.symbols_of_death.remains>=(2.2-talent.flagellation.enabled)|variable.shd_threshold)|talent.shadow_dance&cooldown.secret_technique.remains<=9&(spell_targets.shuriken_storm<=3|talent.danse_macabre)|buff.flagellation.up|buff.flagellation_persist.remains>=6|spell_targets.shuriken_storm>=4&cooldown.symbols_of_death.remains>10)&variable.rotten_threshold
actions.stealth_cds+=/shadow_dance,if=variable.shd_combo_points&fight_remains<cooldown.symbols_of_death.remains|!talent.shadow_dance&dot.rupture.ticking&spell_targets.shuriken_storm<=4&variable.rotten_threshold
]]
	self.shd_threshold = ShadowDance:ChargesFractional() >= (ShadowDance:MaxCharges() - 0.25)
	self.rotten_threshold = TheRotten:Down() or Player.enemies > 1 or (Player.combo_points.current <= 2 and TheRotten:Up() and Player.set_bonus.t30 < 2)
	if Vanish:Usable() and not self.shd_threshold and Player.combo_points.deficit > 1 and (not DanseMacabre.known or Player.enemies >= 3) and (not Flagellation.known or not Flagellation:Ready(60) or (Target.boss and Target.timeToDie < (30 * Vanish:Charges()))) then
		return UseCooldown(Vanish)
	end
	if Shadowmeld:Usable() and not self.shd_threshold and Player.energy.deficit >= 10 and Player.combo_points.deficit > 4 then
		Player.pool_energy = 80
		return UseCooldown(Shadowmeld)
	end
	self.shd_combo_points = Player.combo_points.current <= 1
	if Player.enemies > (4 - (ShurikenTornado.known and 2 or 0)) or (self.priority_rotation and Player.enemies >= 4) then
		self.shd_combo_points = Player.combo_points.deficit <= 1
	end
	if Player.enemies == (4 - (SealFate.known and 1 or 0)) then
		self.shd_combo_points = true
	end
	if ShadowDance:Usable() and self.rotten_threshold and (
		(self.shd_combo_points and (self.shd_threshold or (ShadowDance:MaxCharges() < 2 and SymbolsOfDeath:Remains() >= (2.2 - (Flagellation.known and 1 or 0))))) or
		(SecretTechnique.known and ShadowDance:MaxCharges() >= 2 and SecretTechnique:Ready(9) and (Player.enemies <= 3 or DanseMacabre.known)) or
		(Flagellation.known and (Flagellation.buff:Up() or Flagellation.persist:Remains() >= 6)) or
		(Player.enemies >= 4 and not SymbolsOfDeath:Ready(10))
	) then
		return UseCooldown(ShadowDance)
	end
end

APL[SPEC.SUBTLETY].finish = function(self)
--[[
actions.finish=variable,name=secret_condition,value=buff.shadow_dance.up&(!talent.danse_macabre|buff.danse_macabre.stack>=5|(buff.danse_macabre.stack>=3&(!buff.premeditation.up|spell_targets.shuriken_storm>2)))
actions.finish+=/variable,name=premed_snd_condition,value=talent.premeditation.enabled&spell_targets.shuriken_storm<5
actions.finish+=/slice_and_dice,if=!variable.premed_snd_condition&spell_targets.shuriken_storm<6&!buff.shadow_dance.up&buff.slice_and_dice.remains<fight_remains&refreshable
actions.finish+=/slice_and_dice,if=variable.premed_snd_condition&cooldown.shadow_dance.charges_fractional<1.75&buff.slice_and_dice.remains<cooldown.symbols_of_death.remains&(cooldown.shadow_dance.ready&buff.symbols_of_death.remains-buff.shadow_dance.remains<1.2)
actions.finish+=/variable,name=skip_rupture,value=buff.thistle_tea.up&spell_targets.shuriken_storm=1|buff.shadow_dance.up&(spell_targets.shuriken_storm=1|dot.rupture.ticking&spell_targets.shuriken_storm>=2)
actions.finish+=/rupture,if=(!variable.skip_rupture|variable.priority_rotation)&target.time_to_die-remains>6&refreshable
actions.finish+=/rupture,if=!variable.skip_rupture&buff.finality_rupture.up&cooldown.shadow_dance.remains<12&cooldown.shadow_dance.charges_fractional<=1&spell_targets.shuriken_storm=1&(talent.dark_brew|talent.danse_macabre)
actions.finish+=/cold_blood,if=variable.secret_condition&cooldown.secret_technique.ready
actions.finish+=/secret_technique,if=variable.secret_condition&(!talent.cold_blood|cooldown.cold_blood.remains>buff.shadow_dance.remains-2)
actions.finish+=/rupture,cycle_targets=1,if=!variable.skip_rupture&!variable.priority_rotation&spell_targets.shuriken_storm>=2&target.time_to_die>=(2*combo_points)&refreshable
actions.finish+=/rupture,if=!variable.skip_rupture&remains<cooldown.symbols_of_death.remains+10&cooldown.symbols_of_death.remains<=5&target.time_to_die-remains>cooldown.symbols_of_death.remains+5
actions.finish+=/black_powder,if=!variable.priority_rotation&spell_targets>=3|!used_for_danse&buff.shadow_dance.up&spell_targets.shuriken_storm=2&talent.danse_macabre
actions.finish+=/slice_and_dice,if=variable.premed_snd_condition&refreshable&buff.shadow_dance.down&buff.symbols_of_death.down&remains<cooldown.shadow_dance.remains&remains<cooldown.symbols_of_death.remains+8&fight_remains>remains+5
actions.finish+=/eviscerate
]]
	self.secret_condition = ShadowDance:Up() and (not DanseMacabre.known or Player.danse_stacks >= 5 or (Player.danse_stacks >= 3 and (Premeditation:Down() or Player.enemies > 2)))
	self.premed_snd_condition = Premeditation.known and Player.enemies < 5
	if SliceAndDice:Usable(0, true) and not Player.combo_points.anima_charged[Player.combo_points.current] then
		if not self.premed_snd_condition and Player.enemies < 6 and SliceAndDice:Refreshable() and ShadowDance:Down() and SliceAndDice:Remains() < Target.timeToDie then
			return Pool(SliceAndDice)
		end
		if self.premed_snd_condition and ShadowDance:ChargesFractional() < 1.75 and SliceAndDice:Remains() < SymbolsOfDeath:Cooldown() and ShadowDance:Ready() and (SymbolsOfDeath:Remains() - ShadowDance:Remains()) < 1.2 then
			return Pool(SliceAndDice)
		end
	end
	self.use_rupture = Rupture:Refreshable() and Target.timeToDie >= (Rupture:Remains() + ((4 * Player.combo_points.effective) * Player.haste_factor))
	self.skip_rupture = (ThistleTea:Up() and Player.enemies == 1) or (ShadowDance:Up() and (Player.enemies == 1 or (Player.enemies >= 2 and Rupture:Up())))
	if self.use_rupture and Rupture:Usable(0, true) then
		if (not Player.stealthed or Rupture:Down()) and (not self.skip_rupture or self.priority_rotation) then
			return Pool(Rupture)
		end
		if not self.skip_rupture and Player.enemies == 1 and Finality.Rupture:Up() and ShadowDance:Ready(12) and ShadowDance:ChargesFractional() <= 1 and (DarkBrew.known or DanseMacabre.known) then
			return Pool(Rupture)
		end
	end
	if ColdBlood:Usable() and self.secret_condition and SecretTechnique:Ready() then
		UseCooldown(ColdBlood)
	end
	if SecretTechnique:Usable(0, true) and self.secret_condition and (not ColdBlood.known or ColdBlood:Up() or ColdBlood:Ready() or not ColdBlood:Ready(ShadowDance:Remains() - 2)) then
		return Pool(SecretTechnique)
	end
	if self.use_rupture and Rupture:Usable(0, true) and not self.skip_rupture and (
		(not self.priority_rotation and Player.enemies >= 2) or
		(Rupture:Remains() < (SymbolsOfDeath:Cooldown() + 10) and SymbolsOfDeath:Ready(5) and (Target.timeToDie - Rupture:Remains()) > (SymbolsOfDeath:Cooldown() + 5))
	) then
		return Pool(Rupture)
	end
	if BlackPowder:Usable(0, true) and (
		(not self.priority_rotation and Player.enemies >= 3) or
		(Player.danse_stacks >= 1 and Player.enemies >= 2 and not DanseMacabre:UsedFor(BlackPowder))
	) then
		return Pool(BlackPowder)
	end
	if SliceAndDice:Usable(0, true) and not Player.combo_points.anima_charged[Player.combo_points.current] and self.premed_snd_condition and SliceAndDice:Refreshable() and ShadowDance:Down() and SymbolsOfDeath:Down() and SliceAndDice:Remains() < ShadowDance:Cooldown() and SliceAndDice:Remains() < (SymbolsOfDeath:Cooldown() + 8) and (Player.enemies > 1 or Target.timeToDie > (SliceAndDice:Remains() + 5)) then
		return Pool(SliceAndDice)
	end
	if Eviscerate:Usable(0, true) then
		return Pool(Eviscerate)
	end
end

APL[SPEC.SUBTLETY].build = function(self)
--[[
actions.build=shuriken_storm,if=spell_targets>=2+(talent.gloomblade&buff.lingering_shadow.remains>=6|buff.perforated_veins.up)
actions.build+=/variable,name=anima_helper,value=!talent.echoing_reprimand.enabled|!(variable.is_next_cp_animacharged&(time_to_sht.3.plus<0.5|time_to_sht.4.plus<1)&energy<60)
actions.build+=/gloomblade,if=variable.anima_helper
actions.build+=/backstab,if=variable.anima_helper
]]
	if ShurikenStorm:Usable() and Player.enemies >= (2 + (((Gloomblade.known and LingeringShadow.known and LingeringShadow:Remains() >= 6) or (PerforatedVeins.known and PerforatedVeins:Up())) and 1 or 0)) then
		return ShurikenStorm
	end
	self.anima_helper = not EchoingReprimand.known or not (self.is_next_cp_animacharged and (ShadowTechniques:TimeTo(3) < 0.5 or ShadowTechniques:TimeTo(4) < 1) and Player.energy.current < 60)
	if Gloomblade:Usable() and self.anima_helper then
		return Gloomblade
	end
	if Backstab:Usable() and self.anima_helper then
		return Backstab
	end
end

APL[SPEC.SUBTLETY].stealthed = function(self)
--[[
actions.stealthed=shadowstrike,if=(buff.stealth.up|buff.vanish.up)&(spell_targets.shuriken_storm<4|variable.priority_rotation)
actions.stealthed+=/variable,name=gloomblade_condition,value=buff.danse_macabre.stack<5&(combo_points.deficit=2|combo_points.deficit=3)&(buff.premeditation.up|effective_combo_points<7)&(spell_targets.shuriken_storm<=8|talent.lingering_shadow)
actions.stealthed+=/shuriken_storm,if=variable.gloomblade_condition&buff.silent_storm.up&!debuff.find_weakness.remains&talent.improved_shuriken_storm.enabled|combo_points<=1&!used_for_danse&spell_targets.shuriken_storm=2&talent.danse_macabre
actions.stealthed+=/gloomblade,if=variable.gloomblade_condition&!used_for_danse|combo_points<=2&buff.the_rotten.up&spell_targets.shuriken_storm<=3
actions.stealthed+=/backstab,if=variable.gloomblade_condition&talent.danse_macabre&buff.danse_macabre.stack<=2&spell_targets.shuriken_storm<=2
actions.stealthed+=/call_action_list,name=finish,if=variable.effective_combo_points>=cp_max_spend
actions.stealthed+=/call_action_list,name=finish,if=buff.shuriken_tornado.up&combo_points.deficit<=2
actions.stealthed+=/call_action_list,name=finish,if=spell_targets.shuriken_storm>=4-talent.seal_fate&variable.effective_combo_points>=4
actions.stealthed+=/call_action_list,name=finish,if=combo_points.deficit<=1+(talent.seal_fate|talent.deeper_stratagem|talent.secret_stratagem)
actions.stealthed+=/gloomblade,if=buff.perforated_veins.stack>=5&spell_targets.shuriken_storm<3
actions.stealthed+=/backstab,if=buff.perforated_veins.stack>=5&spell_targets.shuriken_storm<3
actions.stealthed+=/shadowstrike,if=stealthed.sepsis&spell_targets.shuriken_storm<4
actions.stealthed+=/shuriken_storm,if=spell_targets>=3+buff.the_rotten.up&(!buff.premeditation.up|spell_targets>=7&!variable.priority_rotation)
actions.stealthed+=/shadowstrike,if=debuff.find_weakness.remains<=1|cooldown.symbols_of_death.remains<18&debuff.find_weakness.remains<cooldown.symbols_of_death.remains
actions.stealthed+=/shadowstrike
]]
	if Shadowstrike:Usable() and (Stealth:Up() or Vanish:Up()) and (Player.enemies < 4 or self.priority_rotation) then
		return Shadowstrike
	end
	self.gloomblade_condition = Player.danse_stacks < 5 and between(Player.combo_points.deficit, 2, 3) and (Premeditation:Up() or Player.combo_points.effective < 7) and (Player.enemies <= 8 or LingeringShadow.known)
	if ShurikenStorm:Usable() and (
		(self.gloomblade_condition and ImprovedShurikenStorm.known and SilentStorm:Up() and FindWeakness:Down()) or
		(Player.danse_stacks >= 1 and Player.combo_points.current <= 1 and Player.enemies >= 2 and not DanseMacabre:UsedFor(ShurikenStorm))
	) then
		return ShurikenStorm
	end
	if Gloomblade:Usable() and (
		(self.gloomblade_condition and Player.danse_stacks >= 1 and not DanseMacabre:UsedFor(Gloomblade)) or
		(TheRotten.known and Player.combo_points.current <= 2 and Player.enemies <= 3 and TheRotten:Up())
	) then
		return Gloomblade
	end
	if Backstab:Usable() and self.gloomblade_condition and between(Player.danse_stacks, 1, 2) and Player.enemies <= 2 and not DanseMacabre:UsedFor(Backstab) then
		return Backstab
	end
	if (
		Player.combo_points.effective >= Player.combo_points.max_spend or
		(ShurikenTornado.known and ShurikenTornado:Up() and Player.combo_points.deficit <= 2) or
		(Player.combo_points.effective >= 4 and Player.enemies >= (4 - (SealFate.known and 1 or 0))) or
		(Player.combo_points.deficit <= (1 + ((SealFate.known or DeeperStratagem.known or SecretStratagem.known) and 1 or 0)))
	) then
		local apl = self:finish()
		if apl then return apl end
	end
	if PerforatedVeins.known and Gloomblade:Usable() and Player.enemies < 3 and PerforatedVeins:Stack() >= 5 then
		return Gloomblade
	end
	if PerforatedVeins.known and Backstab:Usable() and Player.enemies < 3 and PerforatedVeins:Stack() >= 5 then
		return Backstab
	end
	if Sepsis.known and Shadowstrike:Usable() and Sepsis.buff:Up() and Player.enemies < 4 then
		return Shadowstrike
	end
	if ShurikenStorm:Usable() and Player.enemies >= (3 + ((TheRotten.known and TheRotten:Up()) and 1 or 0)) and (Premeditation:Down() or (Player.enemies >= 7 and not self.priority_rotation)) then
		return ShurikenStorm
	end
	if Shadowstrike:Usable() then
		return Shadowstrike
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
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
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

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
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
	assassinPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	assassinCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
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
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_center, text_cd, text_tl, text_tr

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
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
	end
	if Player.cd and Player.cd.requires_react then
		local react = Player.cd:React()
		if react > 0 then
			text_cd = format('%.1f', react)
		end
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			text_center = format('POOL %d', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.danse_stacks > 0 then
		text_tr = Player.danse_stacks
	end
	if Player.stealth_remains > 0 then
		text_tl = format('%.1fs', Player.stealth_remains)
	end
	if border ~= assassinPanel.border.overlay then
		assassinPanel.border.overlay = border
		assassinPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	assassinPanel.dimmer:SetShown(dim)
	assassinPanel.text.center:SetText(text_center)
	assassinPanel.text.tl:SetText(text_tl)
	assassinPanel.text.tr:SetText(text_tr)
	--assassinPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	assassinCooldownPanel.text:SetText(text_cd)
	assassinCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		assassinPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.energy_cost > 0 and Player.main:EnergyCost() == 0) or (Player.main.cp_cost > 0 and Player.main:CPCost() == 0) or (Player.main.Free and Player.main:Free())
	end
	if Player.cd then
		assassinCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			assassinCooldownPanel.swipe:SetCooldown(start, duration)
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
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Assassin1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
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
	trackAuras:Remove(dstGUID)
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

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
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
			if RollTheBones.known and RollTheBones.buffs[ability] then
				ability.trigger = RollTheBones.next_trigger
			end
		end
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not ability.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
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
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
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
	if RollTheBones.known and (ability == RollTheBones or (CountTheOdds.known and (ability == Ambush or ability == Dispatch))) then
		RollTheBones.next_trigger = ability
	end
	if EchoingReprimand.known and EchoingReprimand.finishers[ability] and Player.combo_points.anima_charged[Player.combo_points.current] then
		EchoingReprimand[Player.combo_points.current].consume_castGUID = castGUID
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
	if EchoingReprimand.known then
		for i = 2, 5 do
			if ability == EchoingReprimand then
				EchoingReprimand[i].consume_castGUID = nil
				EchoingReprimand[i].consumed = false
			elseif castGUID == EchoingReprimand[i].consume_castGUID then
				EchoingReprimand[i].consume_castGUID = nil
				EchoingReprimand[i].consumed = true
			end
		end
	end
end

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
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end

	Player.set_bonus.t29 = (Player:Equipped(200369) and 1 or 0) + (Player:Equipped(200371) and 1 or 0) + (Player:Equipped(200372) and 1 or 0) + (Player:Equipped(200373) and 1 or 0) + (Player:Equipped(200374) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202495) and 1 or 0) + (Player:Equipped(202496) and 1 or 0) + (Player:Equipped(202497) and 1 or 0) + (Player:Equipped(202498) and 1 or 0) + (Player:Equipped(202500) and 1 or 0)
	Player.set_bonus.t31 = (Player:Equipped(207234) and 1 or 0) + (Player:Equipped(207235) and 1 or 0) + (Player:Equipped(207236) and 1 or 0) + (Player:Equipped(207237) and 1 or 0) + (Player:Equipped(207239) and 1 or 0)

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
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end


function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		assassinPanel.swipe:SetCooldown(start, duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

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
	print(ADDON, '-', desc .. ':', opt_view, ...)
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
				assassinPanel:ClearAllPoints()
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
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
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
	if msg[1] == 'reset' then
		assassinPanel:ClearAllPoints()
		assassinPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
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
		'poisons |cFF00C000on|r/|cFFC00000off|r - show a reminder for poisons (5 minutes outside combat)',
		'priority |cFF00C000on|r/|cFFC00000off|r - use "priority rotation" mode (off by default)',
		'vanish |cFF00C000on|r/|cFFC00000off|r - use Vanish and Shadowmeld while solo (off by default)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Assassin1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
