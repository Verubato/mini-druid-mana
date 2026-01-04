local frame
local manaBar
local powerTypeMana = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local function UpdateManaBar()
	local mana = UnitPower("player", Enum.PowerType.Mana)
	local maxMana = UnitPowerMax("player", Enum.PowerType.Mana)

	manaBar:SetMinMaxValues(0, maxMana)
	manaBar:SetValue(mana)

	local type = UnitPowerType("player")
	local show = type ~= powerTypeMana

	if show then
		manaBar:Show()
	else
		manaBar:Hide()
	end
end

local function OnEvent(_, event, _, powerType)
	if (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") and powerType ~= "MANA" then
		return
	end

	UpdateManaBar()
end

local function InitManaBar()
	manaBar = CreateFrame("StatusBar", "MiniDruidManaBar", PlayerFrame)

	if PlayerFrameManaBar then
		-- classic
		manaBar:SetSize(
			PlayerFrameManaBar:GetWidth(),
			-- subtract a bit for the borders
			PlayerFrameManaBar:GetHeight() - 2
		)
		manaBar:SetPoint("TOPLEFT", PlayerFrameManaBar, "BOTTOMLEFT", 0, 0)
	else
		-- retail
		manaBar:SetSize(125, 9)
		manaBar:SetPoint("BOTTOMLEFT", PlayerFrame, "BOTTOMLEFT", 85, 19)
	end

	manaBar:SetStatusBarTexture("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana")
	manaBar:SetStatusBarColor(1, 1, 1)
	manaBar:SetMinMaxValues(0, 100)
	manaBar:Hide()

	local bg = manaBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	bg:SetVertexColor(0, 0, 0, 0.35)

	if PlayerFrameBottomManagedFramesContainer then
		local point, relativeTo, relativeToPoint, xOffset, yOffset = PlayerFrameBottomManagedFramesContainer:GetPoint()
		PlayerFrameBottomManagedFramesContainer:ClearAllPoints()
		-- shift the combo points frame down a tad
		PlayerFrameBottomManagedFramesContainer:SetPoint(
			point,
			relativeTo,
			relativeToPoint,
			xOffset,
			yOffset - 5
		)
	end

	UpdateManaBar()
end

local function Init()
	local _, _, classId = UnitClass("player")
	local druidClassId = 11

	if classId ~= druidClassId then
		return
	end

	frame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", OnEvent)

	InitManaBar()
end

local function OnEnteringWorld()
	-- ADDON_LOADED is too early
	-- wait until frames have been created before we init
	Init()
end

frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", OnEnteringWorld)
