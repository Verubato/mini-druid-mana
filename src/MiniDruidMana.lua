local _, addon = ...
---@type MiniFramework
local mini = addon.Framework
local frame
local container
local powerTypeMana = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local font = {
	File = "Fonts\\FRIZQT__.TTF",
	Size = 8,
	Flags = "OUTLINE",
}
---@type Db
local db

local function GetManaPercentage()
	if UnitPowerPercent then
		return UnitPowerPercent("player", powerTypeMana, true, CurveConstants.ScaleTo100) or 0
	end

	local mana = UnitPower("player", powerTypeMana)
	local maxMana = UnitPowerMax("player", powerTypeMana)

	return (mana / maxMana) * 100
end

local function UpdateManaBar()
	local mana = UnitPower("player", powerTypeMana)
	local maxMana = UnitPowerMax("player", powerTypeMana)

	local manaBar = container.ManaBar
	local manaPercentageText = container.ManaPercentage
	local manaValueText = container.ManaValue

	manaBar:SetMinMaxValues(0, maxMana)
	manaBar:SetValue(mana)

	if db.TextEnabled then
		local percentage = GetManaPercentage()
		manaPercentageText:SetText(string.format("%d%%", percentage))

		local manaValue = AbbreviateNumbers(mana)
		manaValueText:SetText(manaValue)
	else
		manaPercentageText:SetText("")
		manaValueText:SetText("")
	end

	local type = UnitPowerType("player")
	local show = type ~= powerTypeMana

	if show then
		container:Show()
	else
		container:Hide()
	end
end

local function OnEvent(_, event, _, powerType)
	if (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") and powerType ~= "MANA" then
		return
	end

	UpdateManaBar()
end

local function InitManaBar()
	container = CreateFrame("Frame", "MiniDruidManaContainer", PlayerFrame)

	local leftInset = 2
	local rightInset = 2

	if PlayerFrameManaBar then
		-- classic
		leftInset = 5
		rightInset = 5
		container:SetSize(
			-- add 2 for the border width
			PlayerFrameManaBar:GetWidth() + 2,
			-- subtract 2 for the border height
			PlayerFrameManaBar:GetHeight() - 2
		)
		container:SetPoint("TOPLEFT", PlayerFrameManaBar, "BOTTOMLEFT", 0, 0)
	elseif
		PlayerFrame
		and PlayerFrame.PlayerFrameContent
		and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
		and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
		and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
	then
		-- retail
		leftInset = 2
		rightInset = 4
		local target = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar

		container:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, 0)
		container:SetSize(target:GetWidth() + 2, target:GetHeight())
	elseif PlayerFrame then
		-- unknown scenario
		container:SetSize(125, 12)
		container:SetPoint("BOTTOMLEFT", PlayerFrame, "BOTTOMLEFT", 85, 19)
	end

	local manaBar = CreateFrame("StatusBar", nil, container)
	manaBar:SetAllPoints()
	manaBar:SetStatusBarTexture("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana")
	manaBar:SetStatusBarColor(1, 1, 1)
	manaBar:SetMinMaxValues(0, 100)
	manaBar:Show()

	local bg = manaBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	bg:SetVertexColor(0, 0, 0, 0.35)

	local manaPercentage = manaBar:CreateFontString(nil, "OVERLAY")
	manaPercentage:SetFont(font.File, font.Size, font.Flags)
	manaPercentage:SetPoint("LEFT", container, "LEFT", leftInset, 0)
	manaPercentage:Show()

	local manaValue = manaBar:CreateFontString(nil, "OVERLAY")
	manaValue:SetFont(font.File, font.Size, font.Flags)
	manaValue:SetPoint("RIGHT", container, "RIGHT", -rightInset, 0)
	manaValue:Show()

	if PlayerFrameBottomManagedFramesContainer then
		local point, relativeTo, relativeToPoint, xOffset, yOffset = PlayerFrameBottomManagedFramesContainer:GetPoint()
		PlayerFrameBottomManagedFramesContainer:ClearAllPoints()
		-- shift the combo points frame down a tad
		PlayerFrameBottomManagedFramesContainer:SetPoint(point, relativeTo, relativeToPoint, xOffset, yOffset - 5)
	end

	container.ManaBar = manaBar
	container.ManaPercentage = manaPercentage
	container.ManaValue = manaValue

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
	Init()
end

local function OnAddonLoaded()
	addon.Config:Init()

	db = mini:GetSavedVars()

	-- ADDON_LOADED is too early
	-- wait until frames have been created before we init
	frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", OnEnteringWorld)
end

function addon:Update()
	UpdateManaBar()
end

mini:WaitForAddonLoad(OnAddonLoaded)
