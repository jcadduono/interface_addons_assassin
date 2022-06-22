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
local GetPowerRegen = _G.GetPowerRegen
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
		priority_rotation = false,
		last_poison = {
			lethal = false,
			nonlethal = false,
		},
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
local events = {}

local timer = {
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
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	health = {
		current = 0,
		max = 100,
	},
	energy = {
		current = 0,
		regen = 0,
		max = 100,
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
		t28 = 0,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
	main_freecast = false,
	poison = {},
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
assassinPreviousPanel:Hide()
assassinPreviousPanel:RegisterForDrag('LeftButton')
assassinPreviousPanel:SetScript('OnDragStart', assassinPreviousPanel.StartMoving)
assassinPreviousPanel:SetScript('OnDragStop', assassinPreviousPanel.StopMovingOrSizing)
assassinPreviousPanel:SetMovable(true)
assassinPreviousPanel.icon = assassinPreviousPanel:CreateTexture(nil, 'BACKGROUND')
assassinPreviousPanel.icon:SetAllPoints(assassinPreviousPanel)
assassinPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
assassinPreviousPanel.border = assassinPreviousPanel:CreateTexture(nil, 'ARTWORK')
assassinPreviousPanel.border:SetAllPoints(assassinPreviousPanel)
assassinPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local assassinCooldownPanel = CreateFrame('Frame', 'assassinCooldownPanel', UIParent)
assassinCooldownPanel:SetSize(64, 64)
assassinCooldownPanel:SetFrameStrata('BACKGROUND')
assassinCooldownPanel:Hide()
assassinCooldownPanel:RegisterForDrag('LeftButton')
assassinCooldownPanel:SetScript('OnDragStart', assassinCooldownPanel.StartMoving)
assassinCooldownPanel:SetScript('OnDragStop', assassinCooldownPanel.StopMovingOrSizing)
assassinCooldownPanel:SetMovable(true)
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
assassinInterruptPanel:Hide()
assassinInterruptPanel:RegisterForDrag('LeftButton')
assassinInterruptPanel:SetScript('OnDragStart', assassinInterruptPanel.StartMoving)
assassinInterruptPanel:SetScript('OnDragStop', assassinInterruptPanel.StopMovingOrSizing)
assassinInterruptPanel:SetMovable(true)
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
assassinExtraPanel:Hide()
assassinExtraPanel:RegisterForDrag('LeftButton')
assassinExtraPanel:SetScript('OnDragStart', assassinExtraPanel.StartMoving)
assassinExtraPanel:SetScript('OnDragStop', assassinExtraPanel.StopMovingOrSizing)
assassinExtraPanel:SetMovable(true)
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
		{5, '5+'},
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

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
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

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
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

function autoAoe:Purge()
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

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

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
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
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
	if self.requires_stealth and not Player.stealthed then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
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
			return max(0, expires - Player.ctime - Player.execute_remains)
		end
	end
	return 0
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
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
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
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
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
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
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
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
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
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
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
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
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
		autoAoe:Add(dstGUID, true)
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
			if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, Player.time - oldest.start)))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(max(5, min(self.max_range, self.velocity * (Player.time - self.range_est_start))))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and assassinPreviousPanel.ability == self then
		assassinPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

-- Rogue Abilities
---- Multiple Specializations
local CheapShot = Ability:Add(1833, false, true)
CheapShot.buff_duration = 4
CheapShot.energy_cost = 40
CheapShot.requires_stealth = true
local CrimsonVial = Ability:Add(185311, true, true)
CrimsonVial.buff_duration = 4
CrimsonVial.cooldown_duration = 30
CrimsonVial.energy_cost = 20
local Gouge = Ability:Add(1776, false, true)
Gouge.buff_duration = 4
Gouge.cooldown_duration = 15
Gouge.energy_cost = 25
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
Rupture:AutoAoe(false, 'cast')
local Shiv = Ability:Add(5938, false, true)
Shiv.cooldown_duration = 25
Shiv.energy_cost = 20
local SliceAndDice = Ability:Add(315496, true, true)
SliceAndDice.buff_duration = 6
SliceAndDice.energy_cost = 25
SliceAndDice.cp_cost = 1
local Stealth = Ability:Add(1784, true, true, 115191)
local Vanish = Ability:Add(1856, true, true, 11327)
------ Procs

------ Talents
local Alacrity = Ability:Add(193539, true, true)
Alacrity.buff_duration = 20
local DeeperStratagem = Ability:Add(193531, false, true)
local MarkedForDeath = Ability:Add(137619, false, true)
MarkedForDeath.cooldown_duration = 60
MarkedForDeath.triggers_gcd = false
local Nightstalker = Ability:Add(14062, false, true)
local Subterfuge = Ability:Add(108208, true, true, 115192)
local Vigor = Ability:Add(14983, false, true)
local Weaponmaster = Ability:Add({193537, 200733}, false, true)
------ Poisons
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
local Ambush = Ability:Add(8676, false, true)
Ambush.energy_cost = 50
Ambush.requires_stealth = true
local BetweenTheEyes = Ability:Add(315341, false, true)
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
local SinisterStrike = Ability:Add(193315, false, true)
SinisterStrike.energy_cost = 45
------ Talents
local BladeRush = Ability:Add(271877, false, true, 271881)
BladeRush.cooldown_duration = 45
BladeRush:AutoAoe()
local DirtyTricks = Ability:Add(108216, false, true)
local Dreadblades = Ability:Add(343142, false, true)
Dreadblades.buff_duration = 10
Dreadblades.cooldown_duration = 90
Dreadblades.energy_cost = 30
Dreadblades.aura_target = 'player'
local GhostlyStrike = Ability:Add(196937, false, true)
GhostlyStrike.buff_duration = 10
GhostlyStrike.cooldown_duration = 35
GhostlyStrike.energy_cost = 30
local KillingSpree = Ability:Add(51690, false, true)
KillingSpree.cooldown_duration = 120
KillingSpree:AutoAoe()
local QuickDraw = Ability:Add(196938, true, true)
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
------ Tier Bonuses
local TornadoTrigger = Ability:Add(363592, true, true, 364556) -- T28 4 piece
---- Subtlety
local Backstab = Ability:Add(53, false, true)
Backstab.energy_cost = 35
local BlackPowder = Ability:Add(319175, false, true)
BlackPowder.energy_cost = 35
BlackPowder.cp_cost = 1
BlackPowder:AutoAoe(true)
local Eviscerate = Ability:Add(196819, false, true)
Eviscerate.energy_cost = 35
Eviscerate.cp_cost = 1
local FindWeakness = Ability:Add(316219, false, true, 316220)
FindWeakness.buff_duration = 18
local ShadowBlades = Ability:Add(121471, true, true)
ShadowBlades.buff_duration = 20
ShadowBlades.cooldown_duration = 180
local ShadowDance = Ability:Add(185313, true, true, 185422)
ShadowDance.buff_duration = 5
ShadowDance.cooldown_duration = 60
ShadowDance.requires_charge = true
ShadowDance.triggers_gcd = false
local Shadowstrike = Ability:Add(185438, false, true)
Shadowstrike.energy_cost = 40
Shadowstrike.requires_stealth = true
Shadowstrike:AutoAoe(false)
local ShadowTechniques = Ability:Add(196912, true, true, 196911)
local ShurikenStorm = Ability:Add(197835, false, true)
ShurikenStorm.energy_cost = 35
ShurikenStorm:AutoAoe(true)
local ShurikenToss = Ability:Add(114014, false, true)
ShurikenToss.energy_cost = 40
local SymbolsOfDeath = Ability:Add(212283, true, true)
SymbolsOfDeath.buff_duration = 10
SymbolsOfDeath.cooldown_duration = 30
SymbolsOfDeath.autocrit = Ability:Add(328077, true, true, 227151)
SymbolsOfDeath.autocrit.buff_duration = 10
------ Talents
local Gloomblade = Ability:Add(200758, false, true)
Gloomblade.energy_cost = 35
local DarkShadow = Ability:Add(245687, false, true)
local EnvelopingShadows = Ability:Add(238104, true, true)
local MasterOfShadows = Ability:Add(196976, false, true)
local Premeditation = Ability:Add(343160, true, true, 343173)
local SecretTechnique = Ability:Add(280719, true, true)
SecretTechnique.energy_cost = 30
SecretTechnique.cp_cost = 1
SecretTechnique:AutoAoe(true)
local ShadowFocus = Ability:Add(108209, false, true)
local ShotInTheDark = Ability:Add(257505, true, true, 257506)
local ShurikenTornado = Ability:Add(277925, true, true)
ShurikenTornado.energy_cost = 60
ShurikenTornado.buff_duration = 4
ShurikenTornado.cooldown_duration = 60
ShurikenTornado.tick_interval = 1
ShurikenTornado:AutoAoe(true)
-- Covenant abilities
local EchoingReprimand = Ability:Add(323547, true, true) -- Kyrian
EchoingReprimand.cooldown_duration = 45
EchoingReprimand.buff_duration = 45
EchoingReprimand.energy_cost = 10
EchoingReprimand[2] = Ability:Add(323558, true, true)
EchoingReprimand[3] = Ability:Add(323559, true, true)
EchoingReprimand[4] = Ability:Add(323560, true, true)
EchoingReprimand[5] = Ability:Add(354838, true, true)
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
local EffusiveAnimaAccelerator = Ability:Add(352188, false, true, 353248) -- Kyrian (Forgelite Prime Mikanikos Soulbind)
EffusiveAnimaAccelerator.buff_duration = 8
EffusiveAnimaAccelerator.tick_inteval = 2
EffusiveAnimaAccelerator:AutoAoe(false, 'apply')
local Flagellation = Ability:Add(323654, true, true) -- Venthyr
Flagellation.buff_duration = 12
Flagellation.cooldown_duration = 90
Flagellation.debuff = Ability:Add(323654, false, true)
Flagellation.debuff.buff_duration = 12
local KevinsOozeling = Ability:Add(352110, true, true, 342181) -- Necrolord (Plague Deviser Marileth Soulbind)
local KevinsWrath = Ability:Add(352528, false, true) -- debuff applied by Kevin's Oozeling
KevinsWrath.buff_duration = 30
local LeadByExample = Ability:Add(342156, true, true, 342181) -- Necrolord (Emeni Soulbind)
LeadByExample.buff_duration = 10
local Sepsis = Ability:Add(328305, false, true) -- Night Fae
Sepsis.cooldown_duration = 90
Sepsis.energy_cost = 25
Sepsis.buff = Ability:Add(347037, true, true)
Sepsis.buff.buff_duration = 5
local SerratedBoneSpike = Ability:Add(328547, false, true) -- Necrolord
SerratedBoneSpike.buff_duration = 600
SerratedBoneSpike.cooldown_duration = 30
SerratedBoneSpike.energy_cost = 15
SerratedBoneSpike.requires_charge = true
local SummonSteward = Ability:Add(324739, false, true) -- Kyrian
SummonSteward.cooldown_duration = 300
-- Soulbind conduits
local CountTheOdds = Ability:Add(341546, true, true)
CountTheOdds.conduit_id = 244
local PerforatedVeins = Ability:Add(341567, true, true, 341572)
PerforatedVeins.buff_duration = 12
PerforatedVeins.conduit_id = 248
-- Legendary effects
local AkaarisSoulFragment = Ability:Add(340090, false, true)
AkaarisSoulFragment.bonus_id = 7124
local ConcealedBlunderbuss = Ability:Add(340088, false, true, 340587)
ConcealedBlunderbuss.buff_duration = 10
ConcealedBlunderbuss.bonus_id = 7122
local DeathlyShadows = Ability:Add(340092, true, true, 341202)
DeathlyShadows.buff_duration = 12
DeathlyShadows.bonus_id = 7126
local Finality = Ability:Add(340089, true, true)
Finality.bonus_id = 7123
local GreenskinsWickers = Ability:Add(340085, true, true, 340573)
GreenskinsWickers.buff_duration = 15
GreenskinsWickers.bonus_id = 7119
local InvigoratingShadowdust = Ability:Add(340080, true, true)
InvigoratingShadowdust.bonus_id = 7114
local MarkOfTheMasterAssassin = Ability:Add(340076, true, true, 340094)
MarkOfTheMasterAssassin.buff_duration = 4
MarkOfTheMasterAssassin.bonus_id = 7111
local Obedience = Ability:Add(354703, true, true)
Obedience.bonus_id = 7572
local ResoundingClarity = Ability:Add(354837, true, true)
ResoundingClarity.bonus_id = 7577
local TheRotten = Ability:Add(340091, true, true, 341134)
TheRotten.buff_duration = 30
TheRotten.bonus_id = 7125
local TinyToxicBlade = Ability:Add(340078, true, true)
TinyToxicBlade.bonus_id = 7112
local Unity = Ability:Add(364922, true, true)
Unity.bonus_id = 8127
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
local EternalAugmentRune = InventoryItem:Add(190384)
EternalAugmentRune.buff = Ability:Add(367405, true, true)
local EternalFlask = InventoryItem:Add(171280)
EternalFlask.buff = Ability:Add(307166, true, true)
local PhialOfSerenity = InventoryItem:Add(177278) -- Provided by Summon Steward
PhialOfSerenity.max_charges = 3
local PotionOfPhantomFire = InventoryItem:Add(171349)
PotionOfPhantomFire.buff = Ability:Add(307495, true, true)
local PotionOfSpectralAgility = InventoryItem:Add(171270)
PotionOfSpectralAgility.buff = Ability:Add(307159, true, true)
local SpectralFlaskOfPower = InventoryItem:Add(171276)
SpectralFlaskOfPower.buff = Ability:Add(307185, true, true)
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.BottledFlayedwingToxin = InventoryItem:Add(178742)
Trinket.BottledFlayedwingToxin.buff = Ability:Add(345545, true, true)
Trinket.SoleahsSecretTechnique = InventoryItem:Add(190958)
Trinket.SoleahsSecretTechnique.buff = Ability:Add(368512, true, true)
-- End Inventory Items

-- Start Player API

function Player:Health()
	return self.health.current
end

function Player:HealthMax()
	return self.health.max
end

function Player:HealthPct()
	return self.health.current / self.health.max * 100
end

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

function Player:HasteFactor()
	return self.haste_factor
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
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
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
		if CripplingPoison.known then
			Opt.last_poison.nonlethal = CripplingPoison.spellId
		elseif NumbingPoison.known then
			Opt.last_poison.nonlethal = NumbingPoison.spellId
		end
	end
	if Opt.last_poison.lethal then
		self.poison.lethal = abilities.bySpellId[Opt.last_poison.lethal]
	end
	if Opt.last_poison.nonlethal then
		self.poison.nonlethal = abilities.bySpellId[Opt.last_poison.nonlethal]
	end
end

function Player:UpdateAbilities()
	self.rescan_abilities = false
	self.combo_points.max = UnitPowerMax('player', 4)

	local node
	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		end
		if ability.bonus_id then -- used for checking enchants and Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			node = C_Soulbinds.FindNodeIDActuallyInstalled(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
			if node then
				node = C_Soulbinds.GetNode(node)
				if node then
					if node.conduitID == 0 then
						self.rescan_abilities = true -- rescan on next target, conduit data has not finished loading
					else
						ability.known = node.state == 3
						ability.rank = node.conduitRank
					end
				end
			end
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
	if Unity.known then
		Obedience.known = Flagellation.known
		ResoundingClarity.known = EchoingReprimand.known
	end
	if KevinsOozeling.known then
		KevinsWrath.known = true
	end
	ShadowTechniques.auto_count = 0
	TornadoTrigger.known = PistolShot.known and Player.set_bonus.t28 >= 4

	wipe(abilities.bySpellId)
	wipe(abilities.velocity)
	wipe(abilities.autoAoe)
	wipe(abilities.trackAuras)
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end

	self.combo_points.max_spend = DeeperStratagem.known and 6 or 5
	self:UpdatePoisons()
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == Player.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, duration, remains, spellId, speed_mh, speed_oh
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.pool_energy = nil
	self:UpdateTime()
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.health.current = UnitHealth('player')
	self.health.max = UnitHealthMax('player')
	self.energy.regen = GetPowerRegen()
	self.energy.max = UnitPowerMax('player', 3)
	self.energy.current = UnitPower('player', 3) + (self.energy.regen * self.execute_remains)
	self.energy.current = min(max(self.energy.current, 0), self.energy.max)
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
	self.stealthed = Stealth:Up() or Vanish:Up() or (ShadowDance.known and ShadowDance:Up()) or (Sepsis.known and Sepsis.buff:Up()) or (Shadowmeld.known and Shadowmeld:Up())
	self:UpdateThreat()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	assassinPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
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
	UI:Disappear()
	if UI:ShouldHide() then
		return
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
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		assassinPanel:Show()
		return true
	end
end

function Target:Stunned()
	if CheapShot:Up() or KidneyShot:Up() then
		return true
	end
	return false
end

-- End Target API

-- Start Ability Modifications

function Ability:EnergyCost()
	local cost = self.energy_cost
	if ShadowFocus.known and Player.stealthed then
		cost = cost - (cost * 0.20)
	end
	return cost
end

function CheapShot:EnergyCost()
	if DirtyTricks.known then
		return 0
	end
	return Ability.EnergyCost(self)
end
Gouge.EnergyCost = CheapShot.EnergyCost

function CheapShot:Usable(seconds, pool)
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self, seconds, pool)
end
Gouge.Usable = CheapShot.Usable
KidneyShot.Usable = CheapShot.Usable

function Envenom:Duration()
	return self.buff_duration + Player.combo_points.current
end

function Rupture:Duration()
	return self.buff_duration + (4 * Player.combo_points.current)
end

function SliceAndDice:Duration()
	return self.buff_duration + (6 * Player.combo_points.current)
end

function Vanish:Usable()
	if Player.stealthed or Player.group_size == 1 then
		return false
	end
	return Ability.Usable(self)
end
Shadowmeld.Usable = Vanish.Usable

function ShadowDance:Usable()
	if Player.stealthed then
		return false
	end
	return Ability.Usable(self)
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

function CripplingPoison:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Opt.last_poison.nonlethal = self.spellId
	Player.poison.nonlethal = self
end
NumbingPoison.CastSuccess = CripplingPoison.CastSuccess

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

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.ASSASSINATION] = {},
	[SPEC.OUTLAW] = {},
	[SPEC.SUBTLETY] = {},
}

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
		if Trinket.BottledFlayedwingToxin:Usable() and Trinket.BottledFlayedwingToxin.buff:Remains() < 300 then
			UseCooldown(Trinket.BottledFlayedwingToxin)
		end
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseCooldown(SummonSteward)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
		if not Player.stealthed then
			return Stealth
		end
	else
		if Trinket.BottledFlayedwingToxin:Usable() and Trinket.BottledFlayedwingToxin.buff:Remains() < 10 then
			UseExtra(Trinket.BottledFlayedwingToxin)
		end
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 10 and Player.group_size > 1 then
			UseExtra(Trinket.SoleahsSecretTechnique)
		end
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
	if Opt.pot and PotionOfSpectralAgility:Usable() and (Player:BloodlustActive() or Target.timeToDie <= 60 or Vendetta:Up() and Vanish:Ready(5)) then
		return UseCooldown(PotionOfSpectralAgility)
	end
	if ArcaneTorrent:Usable() and Envenom:Down() and Player.energy.deficit >= 15 + Player.energy_regen_combined * Player.gcd_remains * 1.1 then
		return UseCooldown(ArcaneTorrent)
	end
	if MarkedForDeath:Usable() and Target.timeToDie < Player.combo_points.deficit * 1.5 then
		return UseCooldown(MarkedForDeath)
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
	self.rtb_remains = RollTheBones:Remains(true)
	self.rtb_buffs = RollTheBones:Stack()
	self.rtb_reroll = (self.rtb_buffs < 2 and (Broadside:Down() and (not ConcealedBlunderbuss.known or SkullAndCrossbones:Down()) and (not InvigoratingShadowdust.known or TrueBearing:Down()))) or (self.rtb_buffs == 2 and BuriedTreasure:Up() and GrandMelee:Up())
	self.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or AdrenalineRush:Up() or (Dreadblades.known and Dreadblades:Up()))

	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=apply_poison
actions.precombat+=/flask
actions.precombat+=/augmentation
actions.precombat+=/food
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/marked_for_death,precombat_seconds=10,if=raid_event.adds.in>25
actions.precombat+=/fleshcraft,if=soulbind.pustule_eruption|soulbind.volatile_solvent
actions.precombat+=/roll_the_bones,precombat_seconds=2
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
		if Trinket.BottledFlayedwingToxin:Usable() and Trinket.BottledFlayedwingToxin.buff:Remains() < 300 then
			UseCooldown(Trinket.BottledFlayedwingToxin)
		end
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseCooldown(SummonSteward)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
		if MarkedForDeath:Usable() and Player.combo_points.current < 3 then
			UseCooldown(MarkedForDeath)
		end
		if SliceAndDice:Usable() and SliceAndDice:Remains() < (4 * Player.combo_points.current) and Player.combo_points.current >= 2 and Target.timeToDie > SliceAndDice:Remains() then
			return SliceAndDice
		end
		if RollTheBones:Usable() and (self.rtb_reroll or (Broadside:Down() and self.rtb_remains < 5)) then
			UseCooldown(RollTheBones)
		end
		if not Player.stealthed then
			return Stealth
		end
	else
		if Trinket.BottledFlayedwingToxin:Usable() and Trinket.BottledFlayedwingToxin.buff:Remains() < 10 then
			UseExtra(Trinket.BottledFlayedwingToxin)
		end
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 10 and Player.group_size > 1 then
			UseExtra(Trinket.SoleahsSecretTechnique)
		end
	end
--[[
# Reroll BT + GM or single buffs early other than Broadside, TB with Shadowdust, or SnC with Blunderbuss
actions+=/variable,name=rtb_reroll,value=rtb_buffs<2&(!buff.broadside.up&(!runeforge.concealed_blunderbuss|!buff.skull_and_crossbones.up)&(!runeforge.invigorating_shadowdust|!buff.true_bearing.up))|rtb_buffs=2&buff.buried_treasure.up&buff.grand_melee.up
# Ensure we get full Ambush CP gains and aren't rerolling Count the Odds buffs away
actions+=/variable,name=ambush_condition,value=combo_points.deficit>=2+buff.broadside.up&energy>=50&(!conduit.count_the_odds|buff.roll_the_bones.remains>=10)
# Finish at max possible CP without overflowing bonus combo points, unless for BtE which always should be 5+ CP
actions+=/variable,name=finish_condition,value=combo_points>=cp_max_spend-buff.broadside.up-(buff.opportunity.up*talent.quick_draw.enabled|buff.concealed_blunderbuss.up)|effective_combo_points>=cp_max_spend
# Always attempt to use BtE at 5+ CP, regardless of CP gen waste
actions+=/variable,name=finish_condition,op=reset,if=cooldown.between_the_eyes.ready&effective_combo_points<5
# With multiple targets, this variable is checked to decide whether some CDs should be synced with Blade Flurry
actions+=/variable,name=blade_flurry_sync,value=spell_targets.blade_flurry<2&raid_event.adds.in>20|buff.blade_flurry.remains>1+talent.killing_spree.enabled
actions+=/run_action_list,name=stealth,if=stealthed.all
actions+=/call_action_list,name=cds
actions+=/run_action_list,name=finish,if=variable.finish_condition
actions+=/call_action_list,name=build
actions+=/arcane_torrent,if=energy.deficit>=15+energy.regen
actions+=/arcane_pulse
actions+=/lights_judgment
actions+=/bag_of_tricks
]]
	self.ambush_condition = Player.combo_points.deficit >= (2 + (Broadside:Up() and 1 or 0)) and Player.energy.current >= 50 and (not CountTheOdds.known or not RollTheBones:Ready(30) or ((Broadside:Down() or TrueBearing:Down() or RuthlessPrecision:Down()) and (Broadside:Remains() > 15 or TrueBearing:Remains() > 15 or RuthlessPrecision:Remains() > 15)))
	self.finish_condition = Player.combo_points.current >= (Player.combo_points.max_spend - (Broadside:Up() and 1 or 0) - (((QuickDraw.known and Opportunity:Up()) or (ConcealedBlunderbuss.known and ConcealedBlunderbuss:Up())) and 1 or 0)) or Player.combo_points.effective >= Player.combo_points.max_spend
	if BetweenTheEyes:Ready() and Player.combo_points.effective < 5 then
		self.finish_condition = false
	end
	self.blade_flurry_sync = Player.enemies < 2 or BladeFlurry:Remains() > (1 + (KillingSpree.known and 1 or 0))

	if Player.stealthed then
		return self:stealth()
	end
	self:cds()
	if self.finish_condition then
		return self:finish()
	end
	return self:build()
end

APL[SPEC.OUTLAW].stealth = function(self)
--[[
actions.stealth=dispatch,if=variable.finish_condition
actions.stealth+=/ambush
]]
	if Dispatch:Usable() and self.finish_condition then
		return Dispatch
	end
	if Ambush:Usable() then
		return Ambush
	end
end

APL[SPEC.OUTLAW].cds = function(self)
--[[
# Blade Flurry on 2+ enemies
actions.cds=blade_flurry,if=spell_targets>=2&!buff.blade_flurry.up
# Using Ambush is a 2% increase, so Vanish can be sometimes be used as a utility spell unless using Master Assassin or Deathly Shadows
actions.cds+=/vanish,if=!runeforge.mark_of_the_master_assassin&!runeforge.invigorating_shadowdust&!stealthed.all&variable.ambush_condition&(!runeforge.deathly_shadows|buff.deathly_shadows.down&combo_points<=2)
# With Master Asssassin, sync Vanish with a finisher or Ambush depending on BtE cooldown, or always a finisher with MfD
actions.cds+=/variable,name=vanish_ma_condition,if=runeforge.mark_of_the_master_assassin&!talent.marked_for_death.enabled,value=(!cooldown.between_the_eyes.ready&variable.finish_condition)|(cooldown.between_the_eyes.ready&variable.ambush_condition)
actions.cds+=/variable,name=vanish_ma_condition,if=runeforge.mark_of_the_master_assassin&talent.marked_for_death.enabled,value=variable.finish_condition
actions.cds+=/vanish,if=variable.vanish_ma_condition&master_assassin_remains=0&variable.blade_flurry_sync
actions.cds+=/adrenaline_rush,if=!buff.adrenaline_rush.up
# Fleshcraft for Pustule Eruption if not stealthed and not with Blade Flurry
actions.cds+=/fleshcraft,if=(soulbind.pustule_eruption|soulbind.volatile_solvent)&!stealthed.all&(!buff.blade_flurry.up|spell_targets.blade_flurry<2)&(!buff.adrenaline_rush.up|energy.time_to_max>2)
actions.cds+=/flagellation,target_if=max:target.time_to_die,if=!stealthed.all&(variable.finish_condition|target.time_to_die<13)
actions.cds+=/dreadblades,if=!stealthed.all&combo_points<=2&(!covenant.venthyr|debuff.flagellation.up)&(!talent.marked_for_death|!cooldown.marked_for_death.ready)
actions.cds+=/roll_the_bones,if=master_assassin_remains=0&(variable.rtb_reroll|buff.roll_the_bones.remains<(4-rtb_buffs)&(buff.broadside.down|(variable.finish_condition&buff.ruthless_precision.down&buff.true_bearing.down)))
# If adds are up, snipe the one with lowest TTD. Use when dying faster than CP deficit or without any CP.
actions.cds+=/marked_for_death,line_cd=1.5,target_if=min:target.time_to_die,if=raid_event.adds.up&(target.time_to_die<combo_points.deficit|!stealthed.rogue&combo_points.deficit>=cp_max_spend-1)
# If no adds will die within the next 30s, use MfD on boss without any CP.
actions.cds+=/marked_for_death,if=raid_event.adds.in>30-raid_event.adds.duration&!stealthed.rogue&combo_points.deficit>=cp_max_spend-1&(!covenant.venthyr|cooldown.flagellation.remains>10|debuff.flagellation.up)
# Attempt to sync Killing Spree with Vanish for Master Assassin
actions.cds+=/variable,name=killing_spree_vanish_sync,value=!runeforge.mark_of_the_master_assassin|cooldown.vanish.remains>10|master_assassin_remains>2
# Use in 1-2T if BtE is up and won't cap Energy, or at 3T+ (2T+ with Deathly Shadows) or when Master Assassin is up.
actions.cds+=/killing_spree,if=variable.blade_flurry_sync&variable.killing_spree_vanish_sync&!stealthed.rogue&(debuff.between_the_eyes.up&buff.dreadblades.down&energy.deficit>(energy.regen*2+15)|spell_targets.blade_flurry>(2-buff.deathly_shadows.up)|master_assassin_remains>0)
actions.cds+=/blade_rush,if=variable.blade_flurry_sync&(energy.time_to_max>2&!buff.dreadblades.up&!debuff.flagellation.up|energy<=30|spell_targets>2)
# If using Invigorating Shadowdust, use normal logic in addition to checking major CDs.
actions.cds+=/vanish,if=runeforge.invigorating_shadowdust&covenant.venthyr&!stealthed.all&variable.ambush_condition&(!cooldown.flagellation.ready&(!talent.dreadblades|!cooldown.dreadblades.ready|!debuff.flagellation.up))
actions.cds+=/vanish,if=runeforge.invigorating_shadowdust&!covenant.venthyr&!stealthed.all&(cooldown.echoing_reprimand.remains>6|!cooldown.sepsis.ready|cooldown.serrated_bone_spike.full_recharge_time>20)
actions.cds+=/shadowmeld,if=!stealthed.all&variable.ambush_condition
actions.cds+=/potion,if=buff.bloodlust.react|fight_remains<30|buff.adrenaline_rush.up
actions.cds+=/blood_fury
actions.cds+=/berserking
actions.cds+=/fireblood
actions.cds+=/ancestral_call
actions.cds+=/use_item,name=windscar_whetstone,if=spell_targets.blade_flurry>desired_targets|raid_event.adds.in>60|fight_remains<7
actions.cds+=/use_item,name=cache_of_acquired_treasures,if=buff.acquired_axe.up|fight_remains<25
actions.cds+=/use_item,name=scars_of_fraternal_strife,if=!buff.scars_of_fraternal_strife_4.up|fight_remains<30
# Default conditions for usable items.
actions.cds+=/use_items,slots=trinket1,if=debuff.between_the_eyes.up|trinket.1.has_stat.any_dps|fight_remains<=20
actions.cds+=/use_items,slots=trinket2,if=debuff.between_the_eyes.up|trinket.2.has_stat.any_dps|fight_remains<=20
]]
	if BladeFlurry:Usable() and Player.enemies >= 2 and BladeFlurry:Down() then
		return UseCooldown(BladeFlurry)
	end
	if self.use_cds and Vanish:Usable() and (
		(not MarkOfTheMasterAssassin.known and not InvigoratingShadowdust.known and not Player.stealthed and self.ambush_condition and (not DeathlyShadows.known or (Player.combo_points.effective <= 2 and DeathlyShadows:Down()))) or
		(MarkOfTheMasterAssassin.known and MarkOfTheMasterAssassin:Down() and self.blade_flurry_sync and (
			(MarkedForDeath.known and ((not BetweenTheEyes:Ready() and self.finish_condition) or (BetweenTheEyes:Ready() and self.ambush_condition))) or
			(not MarkedForDeath.known and self.finish_condition)
		))
	) then
		UseExtra(Vanish)
	end
	if self.use_cds and AdrenalineRush:Usable() and AdrenalineRush:Down() then
		return UseCooldown(AdrenalineRush)
	end
	if self.use_cds and Flagellation:Usable() and not Player.stealthed and (self.finish_condition or Target.timeToDie < 13) then
		return UseCooldown(Flagellation)
	end
	if self.use_cds and Dreadblades:Usable() and not Player.stealthed and Player.combo_points.effective <= 2 and (not Flagellation.known or Flagellation.debuff:Up()) and (not MarkedForDeath.known or not MarkedForDeath:Ready()) then
		return UseCooldown(Dreadblades)
	end
	if RollTheBones:Usable() and (not MarkOfTheMasterAssassin.known or MarkOfTheMasterAssassin:Down()) and (not Dreadblades.known or Dreadblades:Down()) and (self.rtb_reroll or (self.rtb_remains < (4 - self.rtb_buffs) and (Broadside:Down() or (self.finish_condition and RuthlessPrecision:Down() and TrueBearing:Down())))) then
		return UseCooldown(RollTheBones)
	end
	if MarkedForDeath:Usable() and (Target.timeToDie < Player.combo_points.deficit or (not Player.stealthed and Player.combo_points.deficit >= (Player.combo_points.max_spend - 1) and (not Flagellation.known or not Flagellation:Ready(10) or Flagellation.debuff:Up()))) then
		return UseCooldown(MarkedForDeath)
	end
	self.killing_spree_vanish_sync = not MarkOfTheMasterAssassin.known or not Vanish:Ready(10) or MarkOfTheMasterAssassin:Remains() > 2
	if self.use_cds and KillingSpree:Usable() and self.blade_flurry_sync and self.killing_spree_vanish_sync and not Player.stealthed and ((BetweenTheEyes:Up() and (not Dreadblades.known or Dreadblades:Down()) and Player.energy.deficit > (Player.energy.regen * 2 + 15)) or Player.enemies > (2 - (DeathlyShadows.known and DeathlyShadows:Up() and 1 or 0)) or (MarkOfTheMasterAssassin.known and MarkOfTheMasterAssassin:Up())) then
		return UseCooldown(KillingSpree)
	end
	if self.use_cds and BladeRush:Usable() and self.blade_flurry_sync and ((Player:EnergyTimeToMax() > 2 and (not Dreadblades.known or Dreadblades:Down()) and (not Flagellation.known or Flagellation.debuff:Down())) or Player.energy.current <= 30 or Player.enemies > 2) then
		return UseCooldown(BladeRush)
	end
	if self.use_cds and Vanish:Usable() and not Player.stealthed and InvigoratingShadowdust.known and (
		(Flagellation.known and self.ambush_condition and not Flagellation:Ready() and (not Dreadblades.known or not Dreadblades:Ready() or Flagellation.debuff:Up())) or
		(not Flagellation.known and ((EchoingReprimand.known and not EchoingReprimand:Ready(6)) or (Sepsis.known and not Sepsis:Ready()) or (SerratedBoneSpike.known and SerratedBoneSpike:FullRechargeTime() > 20)))
	) then
		UseExtra(Vanish)
	end
	if Shadowmeld:Usable() and not Player.stealthed and self.ambush_condition then
		UseExtra(Shadowmeld)
	end
	if Opt.pot and Target.boss and not Player:InArenaOrBattleground() and PotionOfSpectralAgility:Usable() and (Player:BloodlustActive() or Target.timeToDie < 30 or AdrenalineRush:Remains() > 8) then
		return UseCooldown(PotionOfSpectralAgility)
	end
	if Opt.trinket and ((Target.boss and Target.timeToDie < 20) or (MarkOfTheMasterAssassin.known and MarkOfTheMasterAssassin:Up()) or (not MarkOfTheMasterAssassin.known and BetweenTheEyes:Up() and (not GhostlyStrike.known or GhostlyStrike:Up()))) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.OUTLAW].finish = function(self)
--[[
# BtE to keep the Crit debuff up, if RP is up, or for Greenskins, unless the target is about to die.
actions.finish=between_the_eyes,if=target.time_to_die>3&(debuff.between_the_eyes.remains<4|runeforge.greenskins_wickers&!buff.greenskins_wickers.up&combo_points>=4|!runeforge.greenskins_wickers&buff.ruthless_precision.up)
actions.finish+=/slice_and_dice,if=buff.slice_and_dice.remains<fight_remains&refreshable
actions.finish+=/dispatch
]]
	if BetweenTheEyes:Usable(Player:EnergyTimeToMax(50), true) and Target.timeToDie > 3 and (BetweenTheEyes:Remains() < 4 or (GreenskinsWickers.known and Player.combo_points.current >= 4 and GreenskinsWickers:Down()) or (not GreenskinsWickers.known and RuthlessPrecision:Up())) then
		return Pool(BetweenTheEyes)
	end
	if SliceAndDice:Usable(0, true) and SliceAndDice:Refreshable() and (Player.enemies > 1 or SliceAndDice:Remains() < Target.timeToDie) and (not Player.combo_points.anima_charged[Player.combo_points.current] or SliceAndDice:Down()) then
		return Pool(SliceAndDice)
	end
	if Dispatch:Usable(0, true) then
		return Pool(Dispatch)
	end
end

APL[SPEC.OUTLAW].build = function(self)
--[[
actions.build=sepsis
actions.build+=/ghostly_strike,if=debuff.ghostly_strike.remains<=3
actions.build+=/shiv,if=runeforge.tiny_toxic_blade
actions.build+=/echoing_reprimand,if=!soulbind.effusive_anima_accelerator|variable.blade_flurry_sync
# Apply SBS to all targets without a debuff as priority, preferring targets dying sooner after the primary target
actions.build+=/serrated_bone_spike,if=!dot.serrated_bone_spike_dot.ticking
actions.build+=/serrated_bone_spike,target_if=min:target.time_to_die+(dot.serrated_bone_spike_dot.ticking*600),if=!dot.serrated_bone_spike_dot.ticking
# Attempt to use when it will cap combo points and SnD is down, otherwise keep from capping charges
actions.build+=/serrated_bone_spike,if=fight_remains<=5|cooldown.serrated_bone_spike.max_charges-charges_fractional<=0.25|combo_points.deficit=cp_gain&!buff.skull_and_crossbones.up&energy.time_to_max>1
actions.build+=/pistol_shot,if=buff.opportunity.up&(buff.greenskins_wickers.up|buff.concealed_blunderbuss.up|buff.tornado_trigger.up)
# Use Pistol Shot with Opportunity if Combat Potency won't overcap energy, when it will exactly cap CP, or when using Quick Draw
actions.build+=/pistol_shot,if=buff.opportunity.up&(energy.deficit>energy.regen*1.5|!talent.weaponmaster&combo_points.deficit<=1+buff.broadside.up|talent.quick_draw.enabled)
# Use Sinister Strike on targets without the Cache DoT if the trinket is up
actions.build+=/sinister_strike,target_if=min:dot.vicious_wound.remains,if=buff.acquired_axe_driver.up
actions.build+=/sinister_strike
]]
	if Sepsis:Usable() then
		UseCooldown(Sepsis)
	end
	if GhostlyStrike:Usable() and GhostlyStrike:Remains() <= 3 then
		return GhostlyStrike
	end
	if TinyToxicBlade.known and Shiv:Usable() then
		return Shiv
	end
	if EchoingReprimand:Usable() and (not EffusiveAnimaAccelerator.known or self.blade_flurry_sync) then
		return EchoingReprimand
	end
	if SerratedBoneSpike:Usable() and (Target.timeToDie < 5 or SerratedBoneSpike:ChargesFractional() >= 2.75 or (SliceAndDice:Up() and SerratedBoneSpike:Down())) then
		return SerratedBoneSpike
	end
	if PistolShot:Usable() and Opportunity:Up() and (
		QuickDraw.known or
		(GreenskinsWickers.known and GreenskinsWickers:Up()) or
		(ConcealedBlunderbuss.known and ConcealedBlunderbuss:Up()) or
		(TornadoTrigger.known and TornadoTrigger:Up()) or
		Player.energy.deficit > (Player.energy.regen * 1.5) or
		(not Weaponmaster.known and Player.combo_points.deficit <= (1 + (Broadside:Up() and 1 or 0)))
	) then
		return PistolShot
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
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/fleshcraft,if=soulbind.pustule_eruption|soulbind.volatile_solvent
actions.precombat+=/stealth
actions.precombat+=/marked_for_death,precombat_seconds=15
actions.precombat+=/slice_and_dice,precombat_seconds=1
actions.precombat+=/shadow_blades,if=runeforge.mark_of_the_master_assassin
]]
		if Opt.poisons then
			if Player.poison.lethal and Player.poison.lethal:Usable() and Player.poison.lethal:Remains() < 300 then
				return Player.poison.lethal
			end
			if Player.poison.nonlethal and Player.poison.nonlethal:Usable() and Player.poison.nonlethal:Remains() < 300 then
				return Player.poison.nonlethal
			end
		end
		if Trinket.BottledFlayedwingToxin:Usable() and Trinket.BottledFlayedwingToxin.buff:Remains() < 300 then
			UseCooldown(Trinket.BottledFlayedwingToxin)
		end
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseCooldown(SummonSteward)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
		if not Player.stealthed then
			return Stealth
		end
		if MarkedForDeath:Usable() and Player.combo_points.current < 3 then
			UseCooldown(MarkedForDeath)
		end
		if SliceAndDice:Usable() and SliceAndDice:Remains() < (4 * Player.combo_points.current) and Player.combo_points.current >= 2 then
			return SliceAndDice
		end
		if ShadowBlades:Usable() and MarkOfTheMasterAssassin.known then
			UseCooldown(ShadowBlades)
		end
	else
		if Trinket.BottledFlayedwingToxin:Usable() and Trinket.BottledFlayedwingToxin.buff:Remains() < 10 then
			UseExtra(Trinket.BottledFlayedwingToxin)
		end
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 10 and Player.group_size > 1 then
			UseExtra(Trinket.SoleahsSecretTechnique)
		end
	end
--[[
# Restealth if possible (no vulnerable enemies in combat)
actions=stealth
# Interrupt on cooldown to allow simming interactions with that
actions+=/kick
# Used to determine whether cooldowns wait for SnD based on targets.
actions+=/variable,name=snd_condition,value=buff.slice_and_dice.up|spell_targets.shuriken_storm>=6
# Check to see if the next CP (in the event of a ShT proc) is Animacharged
actions+=/variable,name=is_next_cp_animacharged,if=covenant.kyrian,value=combo_points=1&buff.echoing_reprimand_2.up|combo_points=2&buff.echoing_reprimand_3.up|combo_points=3&buff.echoing_reprimand_4.up|combo_points=4&buff.echoing_reprimand_5.up
# Account for ShT reaction time by ignoring low-CP animacharged matches in the 0.5s preceeding a potential ShT proc
actions+=/variable,name=effective_combo_points,value=effective_combo_points
actions+=/variable,name=effective_combo_points,if=covenant.kyrian&effective_combo_points>combo_points&combo_points.deficit>2&time_to_sht.4.plus<0.5&!variable.is_next_cp_animacharged,value=combo_points
# Check CDs at first
actions+=/call_action_list,name=cds
# Apply Slice and Dice at 2+ CP during the first 10 seconds, after that 4+ CP if it expires within the next GCD or is not up
actions+=/slice_and_dice,if=spell_targets.shuriken_storm<6&fight_remains>6&buff.slice_and_dice.remains<gcd.max&combo_points>=4-(time<10)*2
# Run fully switches to the Stealthed Rotation (by doing so, it forces pooling if nothing is available).
actions+=/run_action_list,name=stealthed,if=stealthed.all
# Only change rotation if we have priority_rotation set and multiple targets up.
actions+=/variable,name=use_priority_rotation,value=priority_rotation&spell_targets.shuriken_storm>=2
# Priority Rotation? Let's give a crap about energy for the stealth CDs (builder still respect it). Yup, it can be that simple.
actions+=/call_action_list,name=stealth_cds,if=variable.use_priority_rotation
# Used to define when to use stealth CDs or builders
actions+=/variable,name=stealth_threshold,value=25+talent.vigor.enabled*20+talent.master_of_shadows.enabled*20+talent.shadow_focus.enabled*25+talent.alacrity.enabled*20+25*(spell_targets.shuriken_storm>=4)
# Consider using a Stealth CD when reaching the energy threshold
actions+=/call_action_list,name=stealth_cds,if=energy.deficit<=variable.stealth_threshold
actions+=/call_action_list,name=finish,if=variable.effective_combo_points>=cp_max_spend
# Finish at 4+ without DS or with SoD crit buff, 5+ with DS (outside stealth)
actions+=/call_action_list,name=finish,if=combo_points.deficit<=1|fight_remains<=1&variable.effective_combo_points>=3|buff.symbols_of_death_autocrit.up&variable.effective_combo_points>=4
# With DS also finish at 4+ against 4 targets (outside stealth)
actions+=/call_action_list,name=finish,if=spell_targets.shuriken_storm>=4&variable.effective_combo_points>=4
# Use a builder when reaching the energy threshold
actions+=/call_action_list,name=build,if=energy.deficit<=variable.stealth_threshold
# Lowest priority in all of the APL because it causes a GCD
actions+=/arcane_torrent,if=energy.deficit>=15+energy.regen
actions+=/arcane_pulse
actions+=/lights_judgment
actions+=/bag_of_tricks
]]
	self.snd_condition = Player.enemies >= 6 or SliceAndDice:Up()
	self.is_next_cp_animacharged = EchoingReprimand.known and Player.combo_points.anima_charged[Player.combo_points.current + 1]
	if EchoingReprimand.known and Player.combo_points.effective > Player.combo_points.current and Player.combo_points.deficit > 2 and ShadowTechniques:TimeTo(4) < 0.5 and not self.is_next_cp_animacharged then
		Player.combo_points.effective = Player.combo_points.current
	end
	self.use_priority_rotation = Opt.priority_rotation and Player.enemies >= 2
	if Shadowmeld.known and Stealth:Usable() and Shadowmeld:Up() then
		return Stealth
	end
	self:cds()
	if SliceAndDice:Usable() and Player.enemies < 6 and (Target.timeToDie > 6 or Player.enemies > 1) and SliceAndDice:Remains() < 1 and Player.combo_points.current >= (Player:TimeInCombat() < 10 and 2 or 4) then
		return SliceAndDice
	end
	if Player.stealthed then
		return self:stealthed()
	end
	self.stealth_threshold = 25 + (Vigor.known and 20 or 0) + (MasterOfShadows.known and 20 or 0) + (ShadowFocus.known and 25 or 0) + (Alacrity.known and 20 or 0) + (Player.enemies >= 4 and 25 or 0)
	if Player.energy.deficit <= self.stealth_threshold then
		self:stealth_cds()
	end
	local apl
	if (
		Player.combo_points.effective >= Player.combo_points.max_spend or Player.combo_points.deficit <= 1 or
		(Player.combo_points.effective >= 3 and Player.enemies == 1 and Target.timeToDie < 1) or
		(Player.combo_points.effective >= 4 and (Player.enemies >= 4 or SymbolsOfDeath.autocrit:Up()))
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
# Use Dance off-gcd before the first Shuriken Storm from Tornado comes in.
actions.cds=shadow_dance,use_off_gcd=1,if=!buff.shadow_dance.up&buff.shuriken_tornado.up&buff.shuriken_tornado.remains<=3.5
# (Unless already up because we took Shadow Focus) use Symbols off-gcd before the first Shuriken Storm from Tornado comes in.
actions.cds+=/symbols_of_death,use_off_gcd=1,if=buff.shuriken_tornado.up&buff.shuriken_tornado.remains<=3.5
actions.cds+=/flagellation,target_if=max:target.time_to_die,if=variable.snd_condition&!stealthed.mantle&(spell_targets.shuriken_storm<=1&cooldown.symbols_of_death.up&!talent.shadow_focus.enabled|buff.symbols_of_death.up)&combo_points>=5&target.time_to_die>10
actions.cds+=/vanish,if=(runeforge.mark_of_the_master_assassin&combo_points.deficit<=1-talent.deeper_strategem.enabled|runeforge.deathly_shadows&combo_points<1)&buff.symbols_of_death.up&buff.shadow_dance.up&master_assassin_remains=0&buff.deathly_shadows.down
# Pool for Tornado pre-SoD with ShD ready when not running SF.
actions.cds+=/pool_resource,for_next=1,if=talent.shuriken_tornado.enabled&!talent.shadow_focus.enabled
# Use Tornado pre SoD when we have the energy whether from pooling without SF or just generally.
actions.cds+=/shuriken_tornado,if=spell_targets.shuriken_storm<=1&energy>=60&variable.snd_condition&cooldown.symbols_of_death.up&cooldown.shadow_dance.charges>=1&(!runeforge.obedience|debuff.flagellation.up|spell_targets.shuriken_storm>=(1+4*(!talent.nightstalker.enabled&!talent.dark_shadow.enabled)))&combo_points<=2&!buff.premeditation.up&(!covenant.venthyr|!cooldown.flagellation.up)
actions.cds+=/serrated_bone_spike,cycle_targets=1,if=variable.snd_condition&!dot.serrated_bone_spike_dot.ticking&target.time_to_die>=21&(combo_points.deficit>=(cp_gain>?4))&!buff.shuriken_tornado.up&(!buff.premeditation.up|spell_targets.shuriken_storm>4)|fight_remains<=5&spell_targets.shuriken_storm<3
actions.cds+=/sepsis,if=variable.snd_condition&combo_points.deficit>=1&target.time_to_die>=16
# Use Symbols on cooldown (after first SnD) unless we are going to pop Tornado and do not have Shadow Focus.
actions.cds+=/symbols_of_death,if=variable.snd_condition&(!stealthed.all|buff.perforated_veins.stack<4|spell_targets.shuriken_storm>4&!variable.use_priority_rotation)&(!talent.shuriken_tornado.enabled|talent.shadow_focus.enabled|spell_targets.shuriken_storm>=2|cooldown.shuriken_tornado.remains>2)&(!covenant.venthyr|cooldown.flagellation.remains>10|cooldown.flagellation.up&combo_points>=5)
# If adds are up, snipe the one with lowest TTD. Use when dying faster than CP deficit or not stealthed without any CP.
actions.cds+=/marked_for_death,line_cd=1.5,target_if=min:target.time_to_die,if=raid_event.adds.up&(target.time_to_die<combo_points.deficit|!stealthed.all&combo_points.deficit>=cp_max_spend)
# If no adds will die within the next 30s, use MfD on boss without any CP.
actions.cds+=/marked_for_death,if=raid_event.adds.in>30-raid_event.adds.duration&combo_points.deficit>=cp_max_spend
actions.cds+=/shadow_blades,if=variable.snd_condition&combo_points.deficit>=2&(buff.symbols_of_death.up|fight_remains<=20|!buff.shadow_blades.up&set_bonus.tier28_2pc)
actions.cds+=/echoing_reprimand,if=variable.snd_condition&combo_points.deficit>=2&(!talent.shadow_focus.enabled|!stealthed.all|spell_targets.shuriken_storm>=4)&(variable.use_priority_rotation|spell_targets.shuriken_storm<=4|runeforge.resounding_clarity)
# With SF, if not already done, use Tornado with SoD up.
actions.cds+=/shuriken_tornado,if=(talent.shadow_focus.enabled|spell_targets.shuriken_storm>=2)&variable.snd_condition&buff.symbols_of_death.up&combo_points<=2&(!buff.premeditation.up|spell_targets.shuriken_storm>4)
actions.cds+=/shadow_dance,if=!buff.shadow_dance.up&fight_remains<=8+talent.subterfuge.enabled
actions.cds+=/fleshcraft,if=(soulbind.pustule_eruption|soulbind.volatile_solvent)&energy.deficit>=30&!stealthed.all&buff.symbols_of_death.down
actions.cds+=/potion,if=buff.bloodlust.react|fight_remains<30|buff.symbols_of_death.up&(buff.shadow_blades.up|cooldown.shadow_blades.remains<=10)
actions.cds+=/blood_fury,if=buff.symbols_of_death.up
actions.cds+=/berserking,if=buff.symbols_of_death.up
actions.cds+=/fireblood,if=buff.symbols_of_death.up
actions.cds+=/ancestral_call,if=buff.symbols_of_death.up
actions.cds+=/use_item,name=cache_of_acquired_treasures,if=(covenant.venthyr&buff.acquired_axe.up|!covenant.venthyr&buff.acquired_wand.up)&(spell_targets.shuriken_storm=1&raid_event.adds.in>60|fight_remains<25|variable.use_priority_rotation)|buff.acquired_axe.up&spell_targets.shuriken_storm>1
actions.cds+=/use_item,name=scars_of_fraternal_strife,if=!buff.scars_of_fraternal_strife_4.up|fight_remains<30
# Default fallback for usable items: Use with Symbols of Death.
actions.cds+=/use_items,if=buff.symbols_of_death.up|fight_remains<20
]]
	if ShurikenTornado.known and ShurikenTornado:Up() and ShurikenTornado:Remains() <= 3.5 then
		if ShadowDance:Usable() then
			return UseCooldown(ShadowDance)
		end
		if SymbolsOfDeath:Usable() then
			return UseCooldown(SymbolsOfDeath)
		end
	end
	if Flagellation:Usable() and self.snd_condition and (SymbolsOfDeath:Up() or (Player.enemies <= 1 and not ShadowFocus.known and SymbolsOfDeath:Ready())) and Player.combo_points.current >= 5 and Target.timeToDie > 10 then
		return UseCooldown(Flagellation)
	end
	if Vanish:Usable() and ((MarkOfTheMasterAssassin.known and Player.combo_points.deficit <= (DeeperStratagem.known and 0 or 1)) or (DeathlyShadows.known and Player.combo_points.current < 1)) and SymbolsOfDeath:Up() and ShadowDance:Up() and MarkOfTheMasterAssassin:Down() and DeathlyShadows:Down() then
		return UseCooldown(Vanish)
	end
	if ShurikenTornado:Usable(0, true) and Player.enemies <= 1 and self.snd_condition and not (Stealth:Up() or Vanish:Up() or Shadowmeld:Up()) and SymbolsOfDeath:Ready() and ShadowDance:Charges() >= 1 and (not Obedience.known or Flagellation.debuff:Up() or Player.enemies >= (1 + (not Nightstalker.known and not DarkShadow.known and 4 or 0))) and Player.combo_points.current <= 2 and Premeditation:Down() and (not Flagellation.known or not Flagellation:Ready()) then
		if not ShadowFocus.known then
			Player.pool_energy = 60
			return UseCooldown(ShurikenTornado)
		end
		if Player.energy.current >= 60 then
			return UseCooldown(ShurikenTornado)
		end
	end
	if SerratedBoneSpike:Usable() and ((self.snd_condition and SerratedBoneSpike:Down() and Target.timeToDie >= 21 and (Player.combo_points.deficit >= (1 + SerratedBoneSpike:Ticking())) and ShurikenTornado:Down() and (Premeditation:Down() or Player.enemies > 4)) or (Player.enemies == 1 and Target.timeToDie < 5)) then
		return UseCooldown(SerratedBoneSpike)
	end
	if Sepsis:Usable() and self.snd_condition and Player.combo_points.deficit >= 1 and Target.timeToDie >= 16 then
		return UseCooldown(Sepsis)
	end
	if SymbolsOfDeath:Usable() and self.snd_condition and (not Player.stealthed or (PerforatedVeins.known and PerforatedVeins:Stack() < 4) or (Player.enemies > 4 and not self.use_priority_rotation)) and (not ShurikenTornado.known or ShadowFocus.known or Player.enemies >= 2 or ShurikenTornado:Cooldown() > 2) and (not Flagellation.known or Flagellation:Cooldown() > 10 or (Flagellation:Ready() and Player.combo_points.current >= 5)) then
		return UseCooldown(SymbolsOfDeath)
	end
	if MarkedForDeath:Usable() and (
		(Player.enemies > 1 and Target.timeToDie < Player.combo_points.deficit) or
		(not Player.stealthed and Player.combo_points.deficit >= Player.combo_points.max_spend)
	) then
		return UseCooldown(MarkedForDeath)
	end
	if self.snd_condition then
		if ShadowBlades:Usable() and ShadowBlades:Down() and Player.combo_points.deficit >= 2 and (SymbolsOfDeath:Ready(1) or SymbolsOfDeath:Up() or (Target.boss and Target.timeToDie < 20) or (Player.set_bonus.t28 >= 2 and ShadowBlades:Down())) then
			return UseCooldown(ShadowBlades)
		end
		if EchoingReprimand:Usable() and EchoingReprimand:Down() and Player.combo_points.deficit >= 2 and (not ShadowFocus.known or not Player.stealthed or Player.enemies >= 4) and (self.use_priority_rotation or Player.enemies <= 4 or ResoundingClarity.known) then
			return UseCooldown(EchoingReprimand)
		end
		if ShurikenTornado:Usable() and (ShadowFocus.known or Player.enemies >= 2) and SymbolsOfDeath:Up() and Player.combo_points.current <= 2 and (Premeditation:Down() or Player.enemies > 4) then
			return UseCooldown(ShurikenTornado)
		end
	end
	if ShadowDance:Usable() and Target.boss and Target.timeToDie <= (8 + (Subterfuge.known and 1 or 0)) then
		return UseCooldown(ShadowDance)
	end
	if Opt.pot and Target.boss and PotionOfSpectralAgility:Usable() and (Player:BloodlustActive() or Target.timeToDie < 30 or SymbolsOfDeath:Up() and (ShadowBlades:Up() or ShadowBlades:Ready(10))) then
		return UseCooldown(PotionOfSpectralAgility)
	end
	if Opt.trinket and (Target.timeToDie < 20 or SymbolsOfDeath:Remains() > 6) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.SUBTLETY].stealth_cds = function(self)
--[[
# Helper Variable
actions.stealth_cds=variable,name=shd_threshold,value=cooldown.shadow_dance.charges_fractional>=(1.75-0.75*(covenant.kyrian&set_bonus.tier28_2pc&cooldown.symbols_of_death.remains>=8))
actions.stealth_cds+=/variable,name=shd_threshold,if=runeforge.the_rotten,value=cooldown.shadow_dance.charges_fractional>=1.75|cooldown.symbols_of_death.remains>=16
# Vanish if we are capping on Dance charges. Early before first dance if we have no Nightstalker but Dark Shadow in order to get Rupture up (no Master Assassin).
actions.stealth_cds+=/vanish,if=(!variable.shd_threshold|!talent.nightstalker.enabled&talent.dark_shadow.enabled)&combo_points.deficit>1&!runeforge.mark_of_the_master_assassin&buff.perforated_veins.stack<6
# Pool for Shadowmeld + Shadowstrike unless we are about to cap on Dance charges. Only when Find Weakness is about to run out.
actions.stealth_cds+=/pool_resource,for_next=1,extra_amount=40,if=race.night_elf
actions.stealth_cds+=/shadowmeld,if=energy>=40&energy.deficit>=10&!variable.shd_threshold&combo_points.deficit>1&buff.perforated_veins.stack<6
# CP thresholds for entering Shadow Dance
actions.stealth_cds+=/variable,name=shd_combo_points,value=combo_points.deficit>=2+buff.shadow_blades.up
actions.stealth_cds+=/variable,name=shd_combo_points,value=combo_points.deficit>=3,if=covenant.kyrian
actions.stealth_cds+=/variable,name=shd_combo_points,value=combo_points.deficit<=1,if=variable.use_priority_rotation&spell_targets.shuriken_storm>=4
actions.stealth_cds+=/variable,name=shd_combo_points,value=combo_points.deficit<=1,if=spell_targets.shuriken_storm=4
# Dance during Symbols or above threshold.
actions.stealth_cds+=/shadow_dance,if=(runeforge.the_rotten&cooldown.symbols_of_death.remains<=8|variable.shd_combo_points&(buff.symbols_of_death.remains>=1.2|variable.shd_threshold)|buff.chaos_bane.up|spell_targets.shuriken_storm>=4&cooldown.symbols_of_death.remains>10)&(buff.perforated_veins.stack<4|spell_targets.shuriken_storm>3)
# Burn Dances charges if you play Dark Shadows/Alacrity or before the fight ends if SoD won't be ready in time.
actions.stealth_cds+=/shadow_dance,if=variable.shd_combo_points&fight_remains<cooldown.symbols_of_death.remains|!talent.enveloping_shadows.enabled
]]
	if TheRotten.known then
		self.shd_threshold = ShadowDance:ChargesFractional() >= 1.75 or not SymbolsOfDeath:Ready(16)
	else
		self.shd_threshold = ShadowDance:ChargesFractional() >= ((EchoingReprimand.known and Player.set_bonus.t28 >= 2 and not SymbolsOfDeath:Ready(8)) and 1 or 1.75)
	end
	if Vanish:Usable() and not MarkOfTheMasterAssassin.known and (not self.shd_threshold or not Nightstalker.known and DarkShadow.known) and Player.combo_points.deficit > 1 and (not PerforatedVeins.known or PerforatedVeins:Stack() < 6) then
		return UseCooldown(Vanish)
	end
	if Shadowmeld:Usable() and not self.shd_threshold and Player.energy.deficit >= 10 and Player.combo_points.deficit > 1 and (not PerforatedVeins.known or PerforatedVeins:Stack() < 6) then
		Player.pool_energy = 80
		return UseCooldown(Shadowmeld)
	end
	if Player.enemies == 4 or (self.use_priority_rotation and Player.enemies >= 4) then
		self.shd_combo_points = Player.combo_points.deficit <= 1
	elseif EchoingReprimand.known then
		self.shd_combo_points = Player.combo_points.deficit >= 3
	else
		self.shd_combo_points = Player.combo_points.deficit >= (ShadowBlades:Up() and 3 or 2)
	end
	if ShadowDance:Usable() and (
		not EnvelopingShadows.known or
		(self.shd_combo_points and Player.enemies == 1 and Target.timeToDie < SymbolsOfDeath:Cooldown()) or
		((not PerforatedVeins.known or PerforatedVeins:Stack() < 4 or Player.enemies > 3) and ((TheRotten.known and SymbolsOfDeath:Ready(8)) or (self.shd_combo_points and (SymbolsOfDeath:Remains() >= 1.2 or self.shd_threshold)) or (Player.enemies >= 4 and not SymbolsOfDeath:Ready(10))))
	) then
		return UseCooldown(ShadowDance)
	end
end

APL[SPEC.SUBTLETY].finish = function(self)
--[[
# While using Premeditation, avoid casting Slice and Dice when Shadow Dance is soon to be used, except for Kyrian
actions.finish=variable,name=premed_snd_condition,value=talent.premeditation.enabled&spell_targets.shuriken_storm<(5-covenant.necrolord)&!covenant.kyrian
actions.finish+=/slice_and_dice,if=!variable.premed_snd_condition&spell_targets.shuriken_storm<6&!buff.shadow_dance.up&buff.slice_and_dice.remains<fight_remains&refreshable
actions.finish+=/slice_and_dice,if=variable.premed_snd_condition&cooldown.shadow_dance.charges_fractional<1.75&buff.slice_and_dice.remains<cooldown.symbols_of_death.remains&(cooldown.shadow_dance.ready&buff.symbols_of_death.remains-buff.shadow_dance.remains<1.2)
# Helper Variable for Rupture. Skip during Master Assassin or during Dance with Dark and no Nightstalker.
actions.finish+=/variable,name=skip_rupture,value=master_assassin_remains>0|!talent.nightstalker.enabled&talent.dark_shadow.enabled&buff.shadow_dance.up|spell_targets.shuriken_storm>=(4-stealthed.all*talent.shadow_focus.enabled)
# Keep up Rupture if it is about to run out.
actions.finish+=/rupture,if=(!stealthed.all|!remains)&(!variable.skip_rupture|variable.use_priority_rotation)&target.time_to_die-remains>6&refreshable
actions.finish+=/secret_technique
# Multidotting targets that will live for the duration of Rupture, refresh during pandemic.
actions.finish+=/rupture,cycle_targets=1,if=!variable.skip_rupture&!variable.use_priority_rotation&spell_targets.shuriken_storm>=2&target.time_to_die>=(5+(2*combo_points))&refreshable
# Refresh Rupture early if it will expire during Symbols. Do that refresh if SoD gets ready in the next 5s.
actions.finish+=/rupture,if=!variable.skip_rupture&remains<cooldown.symbols_of_death.remains+10&cooldown.symbols_of_death.remains<=5&target.time_to_die-remains>cooldown.symbols_of_death.remains+5
actions.finish+=/black_powder,if=!variable.use_priority_rotation&spell_targets>=3
actions.finish+=/eviscerate
]]
	self.premed_snd_condition = Premeditation.known and Player.enemies < (SerratedBoneSpike.known and 5 or 4) and not EchoingReprimand.known
	if SliceAndDice:Usable() and not Player.combo_points.anima_charged[Player.combo_points.current] then
		if not self.premed_snd_condition and Player.enemies < 6 and SliceAndDice:Refreshable() and ShadowDance:Down() and SliceAndDice:Remains() < Target.timeToDie then
			return SliceAndDice
		end
		if self.premed_snd_condition and ShadowDance:ChargesFractional() < 1.75 and SliceAndDice:Remains() < SymbolsOfDeath:Cooldown() and ShadowDance:Ready() and (SymbolsOfDeath:Remains() - ShadowDance:Remains()) < 1.2 then
			return SliceAndDice
		end
	end
	self.use_rupture = Rupture:Refreshable() and Target.timeToDie >= (Rupture:Remains() + ((4 * Player.combo_points.effective) * Player.haste_factor))
	self.skip_rupture = (MarkOfTheMasterAssassin.known and MarkOfTheMasterAssassin:Up()) or (not Nightstalker.known and DarkShadow.known and ShadowDance:Up()) or Player.enemies >= (Player.stealthed and ShadowFocus.known and 3 or 4)
	if self.use_rupture and Rupture:Usable(0, true) and (not Player.stealthed or Rupture:Down()) and (not self.skip_rupture or self.use_priority_rotation) then
		return Pool(Rupture)
	end
	if SecretTechnique:Usable(0, true) then
		return Pool(SecretTechnique)
	end
	if self.use_rupture and Rupture:Usable(0, true) and not self.skip_rupture and (
		(not self.use_priority_rotation and Player.enemies >= 2) or
		(Rupture:Remains() < (SymbolsOfDeath:Cooldown() + 10) and SymbolsOfDeath:Ready(5) and (Target.timeToDie - Rupture:Remains()) > (SymbolsOfDeath:Cooldown() + 5))
	) then
		return Pool(Rupture)
	end
	if BlackPowder:Usable(0, true) and not self.use_priority_rotation and Player.enemies >= 3 then
		return Pool(BlackPowder)
	end
	if Eviscerate:Usable(0, true) then
		return Pool(Eviscerate)
	end
end

APL[SPEC.SUBTLETY].build = function(self)
--[[
actions.build=shiv,if=!talent.nightstalker.enabled&runeforge.tiny_toxic_blade&spell_targets.shuriken_storm<5
actions.build+=/shuriken_storm,if=spell_targets>=2&(!covenant.necrolord|cooldown.serrated_bone_spike.max_charges-charges_fractional>=0.25|spell_targets.shuriken_storm>4)&(buff.perforated_veins.stack<=4|spell_targets.shuriken_storm>4&!variable.use_priority_rotation)
actions.build+=/serrated_bone_spike,if=buff.perforated_veins.stack<=2&(cooldown.serrated_bone_spike.max_charges-charges_fractional<=0.25|soulbind.lead_by_example.enabled&!buff.lead_by_example.up|soulbind.kevins_oozeling.enabled&!debuff.kevins_wrath.up)
actions.build+=/gloomblade
# Backstab immediately unless the next CP is Animacharged and we won't cap energy waiting for it.
actions.build+=/backstab,if=!covenant.kyrian|!(variable.is_next_cp_animacharged&(time_to_sht.3.plus<0.5|time_to_sht.4.plus<1)&energy<60)
]]
	if TinyToxicBlade.known and Shiv:Usable() and not Nightstalker.known and Player.enemies < 5 then
		return Shiv
	end
	if ShurikenStorm:Usable() and Player.enemies >= 2 and (not SerratedBoneSpike.known or (SerratedBoneSpike:MaxCharges() - SerratedBoneSpike:ChargesFractional()) >= 0.25 or Player.enemies > 4) and (not PerforatedVeins.known or PerforatedVeins:Stack() <= 4 or (Player.enemies > 4 and not self.use_priority_rotation)) then
		return ShurikenStorm
	end
	if SerratedBoneSpike:Usable() and (not PerforatedVeins.known or PerforatedVeins:Stack() <= 2) and ((SerratedBoneSpike:MaxCharges() - SerratedBoneSpike:ChargesFractional()) <= 0.25 or (LeadByExample.known and LeadByExample:Down()) or (KevinsOozeling.known and KevinsWrath:Down())) then
		return SerratedBoneSpike
	end
	if Gloomblade:Usable() then
		return Gloomblade
	end
	if Backstab:Usable() and (not EchoingReprimand.known or not (self.is_next_cp_animacharged and (ShadowTechniques:TimeTo(3) < 0.5 or ShadowTechniques:TimeTo(4) < 1) and Player.energy.current < 60)) then
		return Backstab
	end
end

APL[SPEC.SUBTLETY].stealthed = function(self)
--[[
# If Stealth/vanish are up, use Shadowstrike to benefit from the passive bonus and Find Weakness, even if we are at max CP (unless using Master Assassin)
actions.stealthed=shadowstrike,if=(buff.stealth.up|buff.vanish.up)&(spell_targets.shuriken_storm<4|variable.use_priority_rotation)&master_assassin_remains=0
actions.stealthed+=/call_action_list,name=finish,if=variable.effective_combo_points>=cp_max_spend
# Finish at 3+ CP without DS / 4+ with DS with Shuriken Tornado buff up to avoid some CP waste situations.
actions.stealthed+=/call_action_list,name=finish,if=buff.shuriken_tornado.up&combo_points.deficit<=2
# Also safe to finish at 4+ CP with exactly 4 targets. (Same as outside stealth.)
actions.stealthed+=/call_action_list,name=finish,if=spell_targets.shuriken_storm>=4&variable.effective_combo_points>=4
# Finish at 4+ CP without DS, 5+ with DS, and 6 with DS after Vanish
actions.stealthed+=/call_action_list,name=finish,if=combo_points.deficit<=1-(talent.deeper_stratagem.enabled&buff.vanish.up)
actions.stealthed+=/shadowstrike,if=stealthed.sepsis&spell_targets.shuriken_storm<4
# Backstab during Shadow Dance when on high PV stacks and Shadow Blades is up.
actions.stealthed+=/backstab,if=conduit.perforated_veins.rank>=8&buff.perforated_veins.stack>=5&buff.shadow_dance.remains>=3&buff.shadow_blades.up&(spell_targets.shuriken_storm<=3|variable.use_priority_rotation)&(buff.shadow_blades.remains<=buff.shadow_dance.remains+2|!covenant.venthyr)
actions.stealthed+=/shiv,if=talent.nightstalker.enabled&runeforge.tiny_toxic_blade&spell_targets.shuriken_storm<5
# Up to 3 targets (no prio) keep up Find Weakness by cycling Shadowstrike.
actions.stealthed+=/shadowstrike,cycle_targets=1,if=!variable.use_priority_rotation&debuff.find_weakness.remains<1&spell_targets.shuriken_storm<=3&target.time_to_die-remains>6
# For priority rotation, use Shadowstrike over Storm with WM against up to 4 targets or if FW is running off (on any amount of targets)
actions.stealthed+=/shadowstrike,if=variable.use_priority_rotation&(debuff.find_weakness.remains<1|talent.weaponmaster.enabled&spell_targets.shuriken_storm<=4)
actions.stealthed+=/shuriken_storm,if=spell_targets>=3+(buff.the_rotten.up|runeforge.akaaris_soul_fragment|set_bonus.tier28_2pc&talent.shadow_focus.enabled)&(buff.symbols_of_death_autocrit.up|!buff.premeditation.up|spell_targets>=5)
# Shadowstrike to refresh Find Weakness and to ensure we can carry over a full FW into the next SoD if possible.
actions.stealthed+=/shadowstrike,if=debuff.find_weakness.remains<=1|cooldown.symbols_of_death.remains<18&debuff.find_weakness.remains<cooldown.symbols_of_death.remains
actions.stealthed+=/gloomblade,if=buff.perforated_veins.stack>=5&conduit.perforated_veins.rank>=13
actions.stealthed+=/shadowstrike
actions.stealthed+=/cheap_shot,if=!target.is_boss&combo_points.deficit>=1&buff.shot_in_the_dark.up&energy.time_to_40>gcd.max
]]
	if Shadowstrike:Usable() and (Stealth:Up() or Vanish:Up()) and (Player.enemies < 4 or self.use_priority_rotation) and (not MarkOfTheMasterAssassin.known or MarkOfTheMasterAssassin:Down()) then
		return Shadowstrike
	end
	if (
		Player.combo_points.effective >= Player.combo_points.max_spend or
		(ShurikenTornado.known and ShurikenTornado:Up() and Player.combo_points.deficit <= 2) or
		(Player.enemies >= 4 and Player.combo_points.effective >= 4) or
		(Player.combo_points.deficit <= (1 - (DeeperStratagem.known and Vanish:Up() and 1 or 0)))
	) then
		local apl = self:finish()
		if apl then return apl end
	end
	if Sepsis.known and Shadowstrike:Usable() and Sepsis.buff:Up() and Player.enemies < 4 then
		return Shadowstrike
	end
	if PerforatedVeins.rank >= 8 and Backstab:Usable() and PerforatedVeins:Stack() >= 5 and ShadowDance:Remains() >= 3 and ShadowBlades:Up() and (Player.enemies <= 3 or self.use_priority_rotation) and (not Flagellation.known or ShadowBlades:Remains() <= (ShadowDance:Remains() + 2)) then
		return Backstab
	end
	if TinyToxicBlade.known and Shiv:Usable() and Nightstalker.known and Player.enemies < 5 then
		return Shiv
	end
	if Shadowstrike:Usable() and (
		(not self.use_priority_rotation and FindWeakness:Remains() < 1 and Player.enemies >= 3 and Target.timeToDie > FindWeakness:Remains() + 6) or
		(self.use_priority_rotation and (FindWeakness:Remains() < 1 or Weaponmaster.known and Player.enemies <= 4))
	) then
		return Shadowstrike
	end
	if ShurikenStorm:Usable() and Player.enemies >= (3 + (((TheRotten.known and TheRotten:Up()) or AkaarisSoulFragment.known or (Player.set_bonus.t28 >= 2 and ShadowFocus.known)) and 1 or 0)) and (SymbolsOfDeath.autocrit:Up() or Premeditation:Down() or Player.enemies >= 5) then
		return ShurikenStorm
	end
	if Shadowstrike:Usable() and (FindWeakness:Remains() < 1 or (SymbolsOfDeath:Ready(18) and FindWeakness:Remains() < SymbolsOfDeath:Cooldown())) then
		return Shadowstrike
	end
	if PerforatedVeins.rank >= 13 and Gloomblade:Usable() and PerforatedVeins:Stack() >= 5 then
		return Gloomblade
	end
	if Shadowstrike:Usable() then
		return Shadowstrike
	end
	if ShotInTheDark.known and CheapShot:Usable() and not Target.boss and Target.stunnable and Player.combo_points.deficit >= 1 and ShotInTheDark:Up() and Player:EnergyTimeToMax(40) > 1 then
		return CheapShot
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
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
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
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	assassinPanel:EnableMouse(Opt.aoe or not Opt.locked)
	assassinPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		assassinPanel:SetScript('OnDragStart', nil)
		assassinPanel:SetScript('OnDragStop', nil)
		assassinPanel:RegisterForDrag(nil)
		assassinPreviousPanel:EnableMouse(false)
		assassinCooldownPanel:EnableMouse(false)
		assassinInterruptPanel:EnableMouse(false)
		assassinExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			assassinPanel:SetScript('OnDragStart', assassinPanel.StartMoving)
			assassinPanel:SetScript('OnDragStop', assassinPanel.StopMovingOrSizing)
			assassinPanel:RegisterForDrag('LeftButton')
		end
		assassinPreviousPanel:EnableMouse(true)
		assassinCooldownPanel:EnableMouse(true)
		assassinInterruptPanel:EnableMouse(true)
		assassinExtraPanel:EnableMouse(true)
	end
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
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.OUTLAW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.SUBTLETY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ASSASSINATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.OUTLAW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.SUBTLETY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
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
	timer.display = 0
	local dim, dim_cd, text_center, text_cd

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main and Player.main.requires_react then
		local react = Player.main:React()
		if react > 0 then
			text_center = format('%.1f', react)
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
	if Player.main and Player.main_freecast then
		if not assassinPanel.freeCastOverlayOn then
			assassinPanel.freeCastOverlayOn = true
			assassinPanel.border:SetTexture(ADDON_PATH .. 'freecast.blp')
		end
	elseif assassinPanel.freeCastOverlayOn then
		assassinPanel.freeCastOverlayOn = false
		assassinPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end

	assassinPanel.dimmer:SetShown(dim)
	assassinPanel.text.center:SetText(text_center)
	--assassinPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	assassinCooldownPanel.text:SetText(text_cd)
	assassinCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.spec]:Main()
	if Player.main then
		assassinPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.energy_cost > 0 and Player.main:EnergyCost() == 0) or (Player.main.cp_cost > 0 and Player.main:CPCost() == 0)
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
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Assassin
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Assassin1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
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
		autoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
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
			if RollTheBones.known and RollTheBones.buffs[ability] then
				ability.trigger = RollTheBones.next_trigger
			end
		end
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
	if Player.rescan_abilities then
		Player:UpdateAbilities()
	end
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_POWER_UPDATE(unitId, powerType)
	if unitId == 'player' and powerType == 'COMBO_POINTS' then
		Player.combo_points.current = UnitPower(unitId, 4)
		Player.combo_points.deficit = Player.combo_points.max - Player.combo_points.current
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_STOP
events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_STOP

function events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitID ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
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

function events:UNIT_SPELLCAST_SUCCEEDED(unitID, castGUID, spellId)
	if unitID ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
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

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		assassinPreviousPanel:Hide()
	end
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
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

	Player.set_bonus.t28 = (Player:Equipped(188901) and 1 or 0) + (Player:Equipped(188902) and 1 or 0) + (Player:Equipped(188903) and 1 or 0) + (Player:Equipped(188905) and 1 or 0) + (Player:Equipped(188907) and 1 or 0)

	Player:ResetSwing(true, true)
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	assassinPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	UI.OnResourceFrameShow()
	Player:Update()
end

function events:SPELL_UPDATE_COOLDOWN()
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

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:SOULBIND_ACTIVATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_NODE_UPDATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_PATH_CHANGED()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = max(1, min(40, GetNumGroupMembers()))
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() events:PLAYER_EQUIPMENT_CHANGED() end)
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
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

assassinPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
for event in next, events do
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
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				assassinPanel:ClearAllPoints()
			end
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
			Opt.alpha = max(0, min(100, tonumber(msg[2]) or 100)) / 100
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
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(0, min(1, tonumber(msg[3]) or 0))
				Opt.glow.color.g = max(0, min(1, tonumber(msg[4]) or 0))
				Opt.glow.color.b = max(0, min(1, tonumber(msg[5]) or 0))
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Assassination specialization', not Opt.hide.assassination)
			end
			if startsWith(msg[2], 'o') then
				Opt.hide.outlaw = not Opt.hide.outlaw
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Outlaw specialization', not Opt.hide.outlaw)
			end
			if startsWith(msg[2], 's') then
				Opt.hide.subtlety = not Opt.hide.subtlety
				events:PLAYER_SPECIALIZATION_CHANGED('player')
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
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Assassin1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
