if select(2, UnitClass('player')) ~= 'ROGUE' then
	DisableAddOn('Assassin')
	return
end

-- useful functions
local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Assassin = {}
local Opt -- use this as a local table reference to Assassin

SLASH_Assassin1, SLASH_Assassin2 = '/assassin', '/ass'
BINDING_HEADER_ASSASSIN = 'Assassin'

local function InitializeVariables()
	local function SetDefaults(t, ref)
		local k, v
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
			color = { r = 1, g = 1, b = 1 }
		},
		hide = {
			assassination = false,
			outlaw = false,
			subtlety = false
		},
		alpha = 1,
		frequency = 0.05,
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
		pot = false,
		poisons = true
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	ASSASSINATION = 1,
	OUTLAW = 2,
	SUBTLETY = 3
}

local events, glows = {}, {}

local abilityTimer, currentSpec, targetMode, combatStartTime = 0, 0, 0, 0

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- tier set equipped pieces count
local Tier = {
	T19P = 0,
	T20P = 0,
	T21P = 0
}

-- legendary item equipped
local ItemEquipped = {
	SephuzsSecret = false
}

local var = {
	gcd = 1.0
}

local targetModes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.ASSASSINATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.OUTLAW] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.SUBTLETY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	}
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
assassinPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
assassinPanel.border:Hide()
assassinPanel.text = assassinPanel:CreateFontString(nil, 'OVERLAY')
assassinPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
assassinPanel.text:SetTextColor(1, 1, 1, 1)
assassinPanel.text:SetAllPoints(assassinPanel)
assassinPanel.text:SetJustifyH('CENTER')
assassinPanel.text:SetJustifyV('CENTER')
assassinPanel.swipe = CreateFrame('Cooldown', nil, assassinPanel, 'CooldownFrameTemplate')
assassinPanel.swipe:SetAllPoints(assassinPanel)
assassinPanel.dimmer = assassinPanel:CreateTexture(nil, 'BORDER')
assassinPanel.dimmer:SetAllPoints(assassinPanel)
assassinPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
assassinPanel.dimmer:Hide()
assassinPanel.targets = assassinPanel:CreateFontString(nil, 'OVERLAY')
assassinPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
assassinPanel.targets:SetPoint('BOTTOMRIGHT', assassinPanel, 'BOTTOMRIGHT', -1.5, 3)
assassinPanel.button = CreateFrame('Button', 'assassinPanelButton', assassinPanel)
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
assassinPreviousPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
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
assassinCooldownPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
assassinCooldownPanel.cd = CreateFrame('Cooldown', nil, assassinCooldownPanel, 'CooldownFrameTemplate')
assassinCooldownPanel.cd:SetAllPoints(assassinCooldownPanel)
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
assassinInterruptPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
assassinInterruptPanel.cast = CreateFrame('Cooldown', nil, assassinInterruptPanel, 'CooldownFrameTemplate')
assassinInterruptPanel.cast:SetAllPoints(assassinInterruptPanel)
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
assassinExtraPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')

-- Start Auto AoE

local autoAoe = {
	abilities = {},
	targets = {}
}

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Assassin_SetTargetMode(1)
		return
	end
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			Assassin_SetTargetMode(i)
			return
		end
	end
end

function autoAoe:add(guid)
	local new = not self.targets[guid]
	self.targets[guid] = GetTime()
	if new then
		self:update()
	end
end

function autoAoe:remove(guid)
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:purge()
	local update, guid, t
	local now = GetTime()
	for guid, t in next, self.targets do
		if now - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	if update then
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability, abilities, abilityBySpellId = {}, {}, {}
Ability.__index = Ability

function Ability.add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		usable_moving = true,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		known = false,
		energy_cost = 0,
		cp_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		auraTarget = buff == 'pet' and 'pet' or buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities[#abilities + 1] = ability
	abilityBySpellId[spellId] = ability
	return ability
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable(seconds)
	if self:energyCost() > var.energy then
		return false
	end
	if self:cpCost() > var.cp then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	if not self.usable_moving and GetUnitSpeed('player') ~= 0 then
		return false
	end
	return self:ready(seconds)
end

function Ability:remains()
	if self.buff_duration > 0 and self:casting() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - var.time - var.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if id == self.spellId or id == self.spellId2 then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
end

function Ability:down()
	return not self:up()
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self:cooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:energyCost()
	return self.energy_cost > 0 and (self.energy_cost / 100 * var.energy_max) or 0
end

function Ability:cpCost()
	return self.cp_cost
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:charges_fractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((var.time - recharge_start) / recharge_time)
end

function Ability:max_charges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return var.cast_ability == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

function Ability:previous()
	if self:channeling() then
		return true
	end
	if var.cast_ability then
		return var.cast_ability == self
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:setAutoAoe(enabled)
	if enabled and not self.auto_aoe then
		self.auto_aoe = true
		self.first_hit_time = nil
		self.targets_hit = {}
		autoAoe.abilities[#autoAoe.abilities + 1] = self
	end
	if not enabled and self.auto_aoe then
		self.auto_aoe = nil
		self.first_hit_time = nil
		self.targets_hit = nil
		local i
		for i = 1, #autoAoe.abilities do
			if autoAoe.abilities[i] == self then
				autoAoe.abilities[i] = nil
				break
			end
		end
	end
end

function Ability:recordTargetHit(guid)
	local t = GetTime()
	self.targets_hit[guid] = t
	if not self.first_hit_time then
		self.first_hit_time = t
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and GetTime() - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		local guid, t
		for guid in next, autoAoe.targets do
			if not self.targets_hit[guid] then
				autoAoe.targets[guid] = nil
			end
		end
		for guid, t in next, self.targets_hit do
			autoAoe.targets[guid] = t
			self.targets_hit[guid] = nil
		end
		autoAoe:update()
	end
end

-- Rogue Abilities
---- Multiple Specializations

local Feint = Ability.add(1966) -- used for GCD
local Kick = Ability.add(1766, false, true)
Kick.cooldown_duration = 15
Kick.triggers_gcd = false
local Stealth = Ability.add(1784, true, true)
local Vanish = Ability.add(1856, true, true, 11327)
------ Talents

------ Poisons
local CripplingPoison = Ability.add(3408, true, true)
CripplingPoison.triggers_gcd = false
CripplingPoison.dot = Ability.add(3409, false, true)
CripplingPoison.dot.buff_duration = 12
local DeadlyPoison = Ability.add(2823, true, true)
DeadlyPoison.triggers_gcd = false
DeadlyPoison.dot = Ability.add(2818, false, true)
DeadlyPoison.dot.buff_duration = 12
DeadlyPoison.dot.tick_interval = 3
local LeechingPoison = Ability.add(108211, true, true)
LeechingPoison.triggers_gcd = false
local WoundPoison = Ability.add(8679, true, true)
WoundPoison.triggers_gcd = false
WoundPoison.dot = Ability.add(8680, false, true)
WoundPoison.dot.buff_duration = 12

------ Procs
local SephuzsSecret = Ability.add(208052, true, true)
SephuzsSecret.cooldown_duration = 30
---- Assassination
local Envenom = Ability.add(32645, true, true)
Envenom.buff_duration = 8
Envenom.energy_cost = 25
Envenom.cp_cost = 1
local FanOfKnives = Ability.add(51723, false, true)
FanOfKnives.energy_cost = 35
FanOfKnives.cp_cost = -1
FanOfKnives:setAutoAoe(true)
local Garrote = Ability.add(703, false, true)
Garrote.buff_duration = 18
Garrote.cooldown_duration = 15
Garrote.energy_cost = 45
Garrote.cp_cost = -1
local Kingsbane = Ability.add(192759, false, true)
Kingsbane.buff_duration = 14
Kingsbane.cooldown_duration = 45
Kingsbane.energy_cost = 35
Kingsbane.cp_cost = -1
local Mutilate = Ability.add(1329, false, true)
Mutilate.energy_cost = 55
Mutilate.cp_cost = -2
local Rupture = Ability.add(1943, false, true)
Rupture.buff_duration = 8
Rupture.energy_cost = 25
Rupture.cp_cost = 1
local SurgeOfToxins = Ability.add(192425, false, true)
SurgeOfToxins.buff_duration = 5
local Vendetta = Ability.add(79140, false, true)
Vendetta.buff_duration = 20
Vendetta.energy_cost = -60
Vendetta.cooldown_duration = 120
Vendetta.triggers_gcd = false
local VirulentPoisons = Ability.add(252277, true, true)
VirulentPoisons.buff_duration = 6
------ Talents
local Anticipation = Ability.add(114015, false, true)
local DeathFromAbove = Ability.add(152150, false, true)
DeathFromAbove.cooldown_duration = 20
DeathFromAbove.energy_cost = 25
DeathFromAbove.cp_cost = 1
local DeeperStratagem = Ability.add(193531, false, true)
local ElaboratePlanning = Ability.add(193640, false, true, 193641)
ElaboratePlanning.buff_duration = 5
local Exsanguinate = Ability.add(200806, false, true)
Exsanguinate.cooldown_duration = 45
Exsanguinate.energy_cost = 25
local Hemorrhage = Ability.add(16511, false, true)
Hemorrhage.buff_duration = 20
Hemorrhage.energy_cost = 30
Hemorrhage.cp_cost = -1
local MarkedForDeath = Ability.add(137619, false, true)
MarkedForDeath.cooldown_duration = 60
MarkedForDeath.cp_cost = -5
MarkedForDeath.triggers_gcd = false
MarkedForDeath:setAutoAoe(true)
local MasterPoisoner = Ability.add(196864, false, true)
local Nightstalker = Ability.add(14062, false, true)
local ShadowFocus = Ability.add(108209, false, true)
local Subterfuge = Ability.add(108208, true, true, 115192)
local ToxicBlade = Ability.add(245388, false, true, 245389)
ToxicBlade.buff_duration = 9
ToxicBlade.cooldown_duration = 25
ToxicBlade.energy_cost = 20
ToxicBlade.cp_cost = -1
local VenomRush = Ability.add(152152, false, true)
local Vigor = Ability.add(14983, false, true)
------ Procs

---- Outlaw

------ Talents

------ Procs

---- Subtlety

------ Talents

------ Procs

-- Tier Bonuses & Legendaries
local MasterAssassinsInitiative = Ability.add(235027, true, true) -- Mantle of the Master Assassin
MasterAssassinsInitiative.buff_duration = 5
-- Racials
local ArcaneTorrent = Ability.add(129597, true, false) -- Blood Elf
ArcaneTorrent.cp_cost = -1
ArcaneTorrent.triggers_gcd = false

-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems = {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local LightforgedAugmentRune = InventoryItem.add(153023)
LightforgedAugmentRune.buff = Ability.add(224001, true, true)
local FlaskOfTheSeventhDemon = InventoryItem.add(127848)
FlaskOfTheSeventhDemon.buff = Ability.add(188033, true, true)
local PotionOfProlongedPower = InventoryItem.add(142117)
PotionOfProlongedPower.buff = Ability.add(229206, true, true)
PotionOfProlongedPower.buff.triggers_gcd = false
local RepurposedFelFocuser = InventoryItem.add(147707)
RepurposedFelFocuser.buff = Ability.add(242551, true, true)
-- End Inventory Items

-- Start Helpful Functions

local function GetExecuteEnergyRegen()
	return var.energy_regen * var.execute_remains - (var.cast_ability and var.cast_ability:energyCost() or 0)
end

local function GetAvailableComboPoints()
	local cp = UnitPower('player', SPELL_POWER_COMBO_POINTS)
	if var.cast_ability then
		cp = min(var.cp_max, max(0, cp - var.cast_ability.cp_cost))
	end
	return cp
end

local function Energy()
	return var.energy
end

local function EnergyDeficit()
	return var.energy_max - var.energy
end

local function EnergyRegen()
	return var.energy_regen
end

local function EnergyMax()
	return var.energy_max
end

local function EnergyTimeToMax()
	local deficit = var.energy_max - var.energy
	if deficit <= 0 then
		return 0
	end
	return deficit / var.energy_regen
end

local function ComboPoints()
	return var.cp
end

local function ComboPointDeficit()
	return var.cp_max - var.cp
end

local function ComboPointsMaxSpend()
	if DeeperStratagem.known then
		return 6
	end
	return 5
end

local function HasteFactor()
	return var.haste_factor
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return targetModes[currentSpec][targetMode][1]
end

local function TimeInCombat()
	return combatStartTime > 0 and var.time - combatStartTime or 0
end

local function Stealthed()
	return Stealth:up() or Vanish:up()
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if id == 2825 or id == 32182 or id == 80353 or id == 90355 or id == 160452 or id == 146555 then
			return true
		end
	end
end

local function TargetIsStunnable()
	if Target.boss then
		return false
	end
	if UnitHealthMax('target') > UnitHealthMax('player') * 25 then
		return false
	end
	return true
end

local function PoisonedBleeds()
	return Rupture:tick_targets_poisoned() + Garrote:tick_targets_poisoned()
end

-- End Helpful Functions

-- Start Ability Modifications

function Envenom:duration()
	return Envenom.buff_duration + var.combo_points - 1
end

function Rupture:duration()
	return Rupture.buff_duration * ((var.combo_points + 1) / 2)
end

function Vanish:usable()
	if not UnitInParty('player') then
		return false
	end
	return Ability.usable(self)
end

local function TickTargetsPoisoned(self)
--[[
	local count = 0
	for target, ends in next, self.tick_targets do
		if DeadlyPoison.tick_targets[target] or WoundPoison.tick_targets[target] then
			count = count + 1
		end
	end
	return count
]]
	return self:up() and (DeadlyPoison:up() or WoundPoison:up()) and 1 or 0
end

Garrote.tick_targets_poisoned = TickTargetsPoisoned
Rupture.tick_targets_poisoned = TickTargetsPoisoned

function SephuzsSecret:cooldown()
	if not self.cooldown_start then
		return 0
	end
	if var.time >= self.cooldown_start + self.cooldown_duration then
		self.cooldown_start = nil
		return 0
	end
	return self.cooldown_duration - (var.time - self.cooldown_start)
end

-- End Ability Modifications

local function UpdateVars()
	local _, start, duration, remains, hp, hp_lost, spellId
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_extra = var.extra
	var.main =  nil
	var.cd = nil
	var.extra = nil
	var.time = GetTime()
	start, duration = GetSpellCooldown(Feint.spellId)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.cast_ability = abilityBySpellId[spellId]
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.energy_regen = GetPowerRegen()
	var.execute_regen = GetExecuteEnergyRegen()
	var.energy_max = UnitPowerMax('player', SPELL_POWER_ENERGY)
	var.energy = min(var.energy_max, floor(UnitPower('player', SPELL_POWER_ENERGY) + var.execute_regen))
	var.cp_max = UnitPowerMax('player', SPELL_POWER_COMBO_POINTS)
	var.cp = GetAvailableComboPoints()
	hp = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[#Target.healthArray + 1] = hp
	Target.timeToDieMax = hp / UnitHealthMax('player') * 5
	Target.healthPercentage = Target.guid == 0 and 100 or (hp / UnitHealthMax('target') * 100)
	hp_lost = Target.healthArray[1] - hp
	Target.timeToDie = hp_lost > 0 and min(Target.timeToDieMax, hp / (hp_lost / 3)) or Target.timeToDieMax
end

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not var.extra or overwrite then
		var.extra = ability
	end
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = function() end
}

APL[SPEC.ASSASSINATION] = function()
	if TimeInCombat() == 0 then
		if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 300 and not FlaskOfTheSeventhDemon.buff:up() then
			return RepurposedFelFocuser
		end
		if LightforgedAugmentRune:usable() and LightforgedAugmentRune.buff:remains() < 300 then
			return LightforgedAugmentRune
		end
		if Opt.poisons then
			if WoundPoison:up() then
				if WoundPoison:remains() < 300 then
					return WoundPoison
				end
			elseif DeadlyPoison:remains() < 300 then
				return DeadlyPoison
			end
			if CripplingPoison:up() then
				if CripplingPoison:remains() < 300 then
					return CripplingPoison
				end
			elseif LeechingPoison.known and LeechingPoison:remains() < 300 then
				return LeechingPoison
			end
		end
		if not Stealthed() then
			return Stealth
		end
		if Opt.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	end
	if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 30 and not FlaskOfTheSeventhDemon.buff:up() then
		UseCooldown(RepurposedFelFocuser)
	end
	if LightforgedAugmentRune:usable() and LightforgedAugmentRune.buff:remains() < 30 then
		UseCooldown(LightforgedAugmentRune)
	end
	if Opt.poisons then
		if WoundPoison:up() then
			if WoundPoison:remains() < 30 then
				UseCooldown(WoundPoison)
			end
		elseif DeadlyPoison:remains() < 30 then
			UseCooldown(DeadlyPoison)
		end
		if CripplingPoison:up() then
			if CripplingPoison:remains() < 30 then
				UseCooldown(CripplingPoison)
			end
		elseif LeechingPoison.known and LeechingPoison:remains() < 30 then
			UseCooldown(LeechingPoison)
		end
	end
	var.energy_regen_combined = var.energy_regen + PoisonedBleeds() * (VenomRush.known and 10 or 7) % 2
	var.energy_time_to_max_combined = EnergyDeficit() % var.energy_regen_combined
	local apl
	if TimeInCombat() > 0 then
		apl = APL.ASSASSINATION_CDS()
		if apl then return apl end
	end
--[[
	if Enemies() > 2 then
		return APL.ASSASSINATION_AOE()
	end
	if Stealthed() then
		return APL.ASSASSINATION_STEALTHED
	end
	apl = APL.ASSASSINATION_MAINTAIN()
	if apl then return apl end
	if not Exsanguinate.known or Exsanguinate:cooldown() > 2 then
		apl = APL.ASSASSINATION_FINISH()
		if apl then return apl end
	end
	if ComboPointDeficit() > (Anticipation.known and 2 or 1) or EnergyDeficit() <= 25 + var.energy_regen_combined then
		apl = APL.ASSASSINATION_BUILD()
		if apl then return apl end
	end
--]]
end

APL.ASSASSINATION_CDS = function()
	if Opt.pot and PotionOfProlongedPower:usable() and (BloodlustActive() or Target.timeToDie <= 60 or Vendetta:up() and Vanish:ready(5)) then
		return UseCooldown(PotionOfProlongedPower)
	end
	if ArcaneTorrent.known and ArcaneTorrent:usable() and Kingsbane:up() and Envenom:down() and EnergyDeficit() >= 15 + var.energy_regen_combined * GCDRemains() * 1.1 then
		return UseCooldown(ArcaneTorrent)
	end
	if MarkedForDeath.known and MarkedForDeath:usable() and Target.timeToDie < ComboPointDeficit() * 1.5 then
		return UseCooldown(MarkedForDeath)
	end
	if Vendetta:usable() and (not Exsanguinate.known or Rupture:ticking()) then
		return UseCooldown(Vendetta)
	end
	if Vanish:usable() and not Stealthed() then
		if Target.timeToDie <= 6 then
			return UseCooldown(Vanish)
		end
		if Nightstalker.known then
			if ComboPoints() >= ComboPointsMaxSpend() and MasterAssassinsInitiative:down() then
				if not Exsanguinate.known and Vendetta:up() then
					return UseCooldown(Vanish)
				elseif Exsanguinate.known and Exsanguinate:ready(1) then
					return UseCooldown(Vanish)
				end
			end
		elseif Subterfuge.known then
			if ItemEquipped.MantleOfTheMasterAssassin and (Vendetta:up() or Target.timeToDie < 10) and MasterAssassinsInitiative:down() then
				return UseCooldown(Vanish)
			elseif not ItemEquipped.MantleOfTheMasterAssassin and Garrote:refreshable() and ((Enemies() <= 3 and ComboPointDeficit() >= 1 + Enemies()) or (Enemies() >= 4 and ComboPointDeficit() >= 4)) then
				return UseCooldown(Vanish)
			end
		elseif ShadowFocus.known and var.energy_time_to_max_combined >= 2 and ComboPointDeficit() >= 4 then
			return UseCooldown(Vanish)
		end
	end
	if ToxicBlade:usable() and (Target.timeToDie <= 6 or ComboPointDeficit() >= 1 + (MasterAssassinsInitiative:remains() >= 0.2 and 1 or 0) and Rupture:remains() > 8 and Vendetta:cooldown() > 10) then
		return UseCooldown(ToxicBlade)
	elseif Kingsbane:usable() and (Target.timeToDie <= 15 or ComboPointDeficit() >= 1 + (MasterAssassinsInitiative:remains() >= 0.2 and 1 or 0) and not Stealthed() and (not ToxicBlade:ready() or (not ToxicBlade.known and Envenom:up()))) then
		return UseCooldown(Kingsbane)
	end
end

APL[SPEC.OUTLAW] = function()
	if TimeInCombat() == 0 then
		if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 300 and not FlaskOfTheSeventhDemon.buff:up() then
			return RepurposedFelFocuser
		end
		if LightforgedAugmentRune:usable() and LightforgedAugmentRune.buff:remains() < 300 then
			return LightforgedAugmentRune
		end
		if not Stealthed() then
			return Stealth
		end
		if Opt.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	end
	if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 30 and not FlaskOfTheSeventhDemon.buff:up() then
		UseCooldown(RepurposedFelFocuser)
	end
	if LightforgedAugmentRune:usable() and LightforgedAugmentRune.buff:remains() < 30 then
		UseCooldown(LightforgedAugmentRune)
	end
end

APL[SPEC.SUBTLETY] = function()
	if TimeInCombat() == 0 then
		if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 300 and not FlaskOfTheSeventhDemon.buff:up() then
			return RepurposedFelFocuser
		end
		if LightforgedAugmentRune:usable() and LightforgedAugmentRune.buff:remains() < 300 then
			return LightforgedAugmentRune
		end
		if not Stealthed() then
			return Stealth
		end
		if Opt.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	end
	if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 30 and not FlaskOfTheSeventhDemon.buff:up() then
		UseCooldown(RepurposedFelFocuser)
	end
	if LightforgedAugmentRune:usable() and LightforgedAugmentRune.buff:remains() < 30 then
		UseCooldown(LightforgedAugmentRune)
	end
end

APL.Interrupt = function()
	if Kick.known and Kick:usable() then
		return Kick
	end
	if ArcaneTorrent.known and ArcaneTorrent:ready() then
		return ArcaneTorrent
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		var.interrupt = nil
		assassinInterruptPanel:Hide()
		return
	end
	var.interrupt = APL.Interrupt()
	if var.interrupt then
		assassinInterruptPanel.icon:SetTexture(var.interrupt.icon)
		assassinInterruptPanel.icon:Show()
		assassinInterruptPanel.border:Show()
	else
		assassinInterruptPanel.icon:Hide()
		assassinInterruptPanel.border:Hide()
	end
	assassinInterruptPanel:Show()
	assassinInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
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

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
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
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and var.main and icon == var.main.icon) or
			(Opt.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Opt.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Opt.glow.extra and var.extra and icon == var.extra.icon)
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

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.ASSASSINATION and Opt.hide.assassination) or
		   (currentSpec == SPEC.OUTLAW and Opt.hide.outlaw) or
		   (currentSpec == SPEC.SUBTLETY and Opt.hide.subtlety))

end

local function Disappear()
	assassinPanel:Hide()
	assassinPanel.icon:Hide()
	assassinPanel.border:Hide()
	assassinCooldownPanel:Hide()
	assassinInterruptPanel:Hide()
	assassinExtraPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.extra, var.last_extra = nil
	UpdateGlows()
end

function Assassin_ToggleTargetMode()
	local mode = targetMode + 1
	Assassin_SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end

function Assassin_ToggleTargetModeReverse()
	local mode = targetMode - 1
	Assassin_SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end

function Assassin_SetTargetMode(mode)
	targetMode = min(mode, #targetModes[currentSpec])
	assassinPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end

function Equipped(name, slot)
	local function SlotMatches(name, slot)
		local ilink = GetInventoryItemLink('player', slot)
		if ilink then
			local iname = ilink:match('%[(.*)%]')
			return (iname and iname:find(name))
		end
		return false
	end
	if slot then
		return SlotMatches(name, slot)
	end
	local i
	for i = 1, 19 do
		if SlotMatches(name, i) then
			return true
		end
	end
	return false
end

function EquippedTier(name)
	local slot = { 1, 3, 5, 7, 10, 15 }
	local equipped, i = 0
	for i = 1, #slot do
		if Equipped(name, slot) then
			equipped = equipped + 1
		end
	end
	return equipped
end

local function UpdateDraggable()
	assassinPanel:EnableMouse(Opt.aoe or not Opt.locked)
	if Opt.aoe then
		assassinPanel.button:Show()
	else
		assassinPanel.button:Hide()
	end
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

local function SnapAllPanels()
	assassinPreviousPanel:ClearAllPoints()
	assassinPreviousPanel:SetPoint('BOTTOMRIGHT', assassinPanel, 'BOTTOMLEFT', -10, -5)
	assassinCooldownPanel:ClearAllPoints()
	assassinCooldownPanel:SetPoint('BOTTOMLEFT', assassinPanel, 'BOTTOMRIGHT', 10, -5)
	assassinInterruptPanel:ClearAllPoints()
	assassinInterruptPanel:SetPoint('TOPLEFT', assassinPanel, 'TOPRIGHT', 16, 25)
	assassinExtraPanel:ClearAllPoints()
	assassinExtraPanel:SetPoint('TOPRIGHT', assassinPanel, 'TOPLEFT', -16, 25)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.ASSASSINATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 18 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.OUTLAW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 18 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.SUBTLETY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 18 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		}
	},
	['kui'] = {
		[SPEC.ASSASSINATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.OUTLAW] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.SUBTLETY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		}
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		assassinPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		assassinPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][currentSpec][Opt.snap]
		assassinPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = NamePlatePlayerResourceFrame
	end
	resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
	resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
end

local function UpdateAlpha()
	assassinPanel:SetAlpha(Opt.alpha)
	assassinPreviousPanel:SetAlpha(Opt.alpha)
	assassinCooldownPanel:SetAlpha(Opt.alpha)
	assassinInterruptPanel:SetAlpha(Opt.alpha)
	assassinExtraPanel:SetAlpha(Opt.alpha)
end

local function UpdateHealthArray()
	Target.healthArray = {}
	local i
	for i = 1, floor(3 / Opt.frequency) do
		Target.healthArray[i] = 0
	end
end

local function UpdateCombat()
	abilityTimer = 0
	UpdateVars()
	var.main = APL[currentSpec]()
	if var.main ~= var.last_main then
		if var.main then
			assassinPanel.icon:SetTexture(var.main.icon)
			assassinPanel.icon:Show()
			assassinPanel.border:Show()
		else
			assassinPanel.icon:Hide()
			assassinPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			assassinCooldownPanel.icon:SetTexture(var.cd.icon)
			assassinCooldownPanel:Show()
		else
			assassinCooldownPanel:Hide()
		end
	end
	if var.extra ~= var.last_extra then
		if var.extra then
			assassinExtraPanel.icon:SetTexture(var.extra.icon)
			assassinExtraPanel:Show()
		else
			assassinExtraPanel:Hide()
		end
	end
	if Opt.dimmer then
		if not var.main then
			assassinPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			assassinPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
			assassinPanel.dimmer:Hide()
		else
			assassinPanel.dimmer:Show()
		end
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(Feint.spellId)
			if start <= 0 then
				return assassinPanel.swipe:Hide()
			end
		end
		assassinPanel.swipe:SetCooldown(start, duration)
		assassinPanel.swipe:Show()
	end
end

function events:ADDON_LOADED(name)
	if name == 'Assassin' then
		Opt = Assassin
		if not Opt.frequency then
			print('It looks like this is your first time running Assassin, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Assassin1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] Assassin is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeVariables()
		UpdateHealthArray()
		UpdateDraggable()
		UpdateAlpha()
		SnapAllPanels()
		assassinPanel:SetScale(Opt.scale.main)
		assassinPreviousPanel:SetScale(Opt.scale.previous)
		assassinCooldownPanel:SetScale(Opt.scale.cooldown)
		assassinInterruptPanel:SetScale(Opt.scale.interrupt)
		assassinExtraPanel:SetScale(Opt.scale.extra)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED(timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName)
	if Opt.auto_aoe then
		if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
			if dstGUID == var.player then
				autoAoe:add(srcGUID)
			elseif srcGUID == var.player then
				autoAoe:add(dstGUID)
			end
		elseif eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
			autoAoe:remove(dstGUID)
		end
	end
	if srcGUID ~= var.player then
		return
	end
	if eventType == 'SPELL_CAST_SUCCESS' then
		local castedAbility = abilityBySpellId[spellId]
		if castedAbility then
			var.last_ability = castedAbility
			if var.last_ability.triggers_gcd then
				PreviousGCD[10] = nil
				table.insert(PreviousGCD, 1, castedAbility)
			end
			if Opt.previous and assassinPanel:IsVisible() then
				assassinPreviousPanel.ability = var.last_ability
				assassinPreviousPanel.border:SetTexture('Interface\\AddOns\\Assassin\\border.blp')
				assassinPreviousPanel.icon:SetTexture(var.last_ability.icon)
				assassinPreviousPanel:Show()
			end
		end
		return
	end
	if eventType == 'SPELL_MISSED' then
		if Opt.previous and Opt.miss_effect and assassinPanel:IsVisible() and assassinPreviousPanel.ability then
			if spellId == assassinPreviousPanel.ability.spellId or spellId == assassinPreviousPanel.ability.spellId2 then
				assassinPreviousPanel.border:SetTexture('Interface\\AddOns\\Assassin\\misseffect.blp')
			end
		end
		return
	end
	if eventType == 'SPELL_DAMAGE' then
		if Opt.auto_aoe then
			local _, ability
			for _, ability in next, autoAoe.abilities do
				if spellId == ability.spellId or spellId == ability.spellId2 then
					ability:recordTargetHit(dstGUID)
				end
			end
		end
		return
	end
--[[
	if eventType == 'SPELL_PERIODIC_DAMAGE' then
		if spellId == DeadlyPoison.dot.spellId then
			print(format('DP tick at now = %.2f', GetTime()))
		end
	end
]]
	if eventType == 'SPELL_AURA_APPLIED' then
		if spellId == SephuzsSecret.spellId then
			SephuzsSecret.cooldown_start = GetTime()
			return
		end
	end
end

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.hostile = true
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateCombat()
			assassinPanel:Show()
			return true
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	Target.boss = Target.level == -1 or (Target.level >= UnitLevel('player') + 2 and not UnitInRaid('player'))
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
		UpdateCombat()
		assassinPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
	if Opt.auto_aoe then
		local guid
		for guid in next, autoAoe.targets do
			autoAoe.targets[guid] = nil
		end
		Assassin_SetTargetMode(1)
	end
	if var.last_ability then
		var.last_ability = nil
		assassinPreviousPanel:Hide()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Tier.T19P = EquippedTier("Doomblade ")
	Tier.T20P = EquippedTier("Fanged Slayer's ")
	Tier.T21P = EquippedTier(" of the Dashing Scoundrel")
	ItemEquipped.SephuzsSecret = Equipped("Sephuz's Secret")
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		local _, i
		for i = 1, #abilities do
			abilities[i].name, _, abilities[i].icon = GetSpellInfo(abilities[i].spellId)
			abilities[i].known = IsPlayerSpell(abilities[i].spellId) or (abilities[i].spellId2 and IsPlayerSpell(abilities[i].spellId2))
		end
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		assassinPreviousPanel.ability = nil
		PreviousGCD = {}
		currentSpec = GetSpecialization() or 0
		Assassin_SetTargetMode(1)
		UpdateTargetInfo()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	var.player = UnitGUID('player')
	UpdateVars()
end

assassinPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Assassin_ToggleTargetMode()
		elseif button == 'RightButton' then
			Assassin_ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Assassin_SetTargetMode(1)
		end
	end
end)

assassinPanel:SetScript('OnUpdate', function(self, elapsed)
	abilityTimer = abilityTimer + elapsed
	if abilityTimer >= Opt.frequency then
		if Opt.auto_aoe then
			local _, ability
			for _, ability in next, autoAoe.abilities do
				ability:updateTargetsHit()
			end
			autoAoe:purge()
		end
		UpdateCombat()
	end
end)

assassinPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	assassinPanel:RegisterEvent(event)
end

function SlashCmdList.Assassin(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('Assassin - Locked: ' .. (Opt.locked and '|cFF00C000On' or '|cFFC00000Off'))
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
			OnResourceFrameShow()
		end
		return print('Assassin - Snap to Blizzard combat resources frame: ' .. (Opt.snap and ('|cFF00C000' .. Opt.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				assassinPreviousPanel:SetScale(Opt.scale.previous)
			end
			return print('Assassin - Previous ability icon scale set to: |cFFFFD000' .. Opt.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				assassinPanel:SetScale(Opt.scale.main)
			end
			return print('Assassin - Main ability icon scale set to: |cFFFFD000' .. Opt.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				assassinCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return print('Assassin - Cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				assassinInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return print('Assassin - Interrupt ability icon scale set to: |cFFFFD000' .. Opt.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'to') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				assassinExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('Assassin - Extra cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Assassin - Action button glow scale set to: |cFFFFD000' .. Opt.scale.glow .. '|r times')
		end
		return print('Assassin - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('Assassin - Icon transparency set to: |cFFFFD000' .. Opt.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.05
			UpdateHealthArray()
		end
		return print('Assassin - Calculation frequency: Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Assassin - Glowing ability buttons (main icon): ' .. (Opt.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Assassin - Glowing ability buttons (cooldown icon): ' .. (Opt.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Assassin - Glowing ability buttons (interrupt icon): ' .. (Opt.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Assassin - Glowing ability buttons (extra icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Assassin - Blizzard default proc glow: ' .. (Opt.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('Assassin - Glow color:', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return print('Assassin - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Assassin - Previous ability icon: ' .. (Opt.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Assassin - Show the Assassin UI without a target: ' .. (Opt.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return print('Assassin - Use Assassin for cooldown management: ' .. (Opt.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
			if not Opt.spell_swipe then
				assassinPanel.swipe:Hide()
			end
		end
		return print('Assassin - Spell casting swipe animation: ' .. (Opt.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
			if not Opt.dimmer then
				assassinPanel.dimmer:Hide()
			end
		end
		return print('Assassin - Dim main ability icon when you don\'t have enough energy to use it: ' .. (Opt.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return print('Assassin - Red border around previous ability when it fails to hit: ' .. (Opt.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Assassin_SetTargetMode(1)
			UpdateDraggable()
		end
		return print('Assassin - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Opt.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return print('Assassin - Only use cooldowns on bosses: ' .. (Opt.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.assassination = not Opt.hide.assassination
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Assassin - Assassination specialization: |cFFFFD000' .. (Opt.hide.assassination and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.outlaw = not Opt.hide.outlaw
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Assassin - Outlaw specialization: |cFFFFD000' .. (Opt.hide.outlaw and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'w') then
				Opt.hide.subtlety = not Opt.hide.subtlety
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Assassin - Subtlety specialization: |cFFFFD000' .. (Opt.hide.subtlety and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('Assassin - Possible hidespec options: |cFFFFD000assassination|r/|cFFFFD000outlaw|r/|cFFFFD000subtlety|r - toggle disabling Assassin for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return print('Assassin - Show an icon for interruptable spells: ' .. (Opt.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return print('Assassin - Automatically change target mode on AoE spells: ' .. (Opt.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return print('Assassin - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('Assassin - Show Prolonged Power potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'poison') then
		if msg[2] then
			Opt.poisons = msg[2] == 'on'
		end
		return print('Assassin - Show Poisons reminder: ' .. (Opt.poisons and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'reset' then
		assassinPanel:ClearAllPoints()
		assassinPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return print('Assassin - Position has been reset to default')
	end
	print('Assassin (version: |cFFFFD000' .. GetAddOnMetadata('Assassin', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Assassin UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Assassin UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Assassin UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Assassin UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Assassin UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Assassin for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough energy to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000assassination|r/|cFFFFD000outlaw|r/|cFFFFD000subtlety|r - toggle disabling Assassin for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show Prolonged Power potions in cooldown UI',
		'poisons |cFF00C000on|r/|cFFC00000off|r - show a reminder for poisons (5 minutes outside combat)',
		'|cFFFFD000reset|r - reset the location of the Assassin UI to default',
	} do
		print('  ' .. SLASH_Assassin1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Contact |cFFFFF569Irq|cFFFFD000-Dalaran|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
