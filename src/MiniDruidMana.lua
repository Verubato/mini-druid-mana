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
local classicBorderFile = "Interface\\CharacterFrame\\UI-CharacterFrame-GroupIndicator"
-- The two layouts PlayerFrame_ToPlayerArt picks between, with and without a bar in the slot.
local playerArt = {
	Flash = "UI-HUD-UnitFrame-Player-PortraitOn-InCombat",
	FlashX = -1.5,
	FlashY = 1,
	ManaMask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask",
}
local alternateArt = {
	Flash = "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource-InCombat",
	FlashX = -2,
	FlashY = 0.5,
	ManaMask = "Unit_BarMask",
}
---@type Db
local db
local hovered = false
-- Blizzard's own bar for mana in a non-mana form, which shares our slot.
local blizzardManaBar

local function GetManaPercentage()
	if UnitPowerPercent then
		return UnitPowerPercent("player", powerTypeMana, true, CurveConstants.ScaleTo100) or 0
	end

	local mana = UnitPower("player", powerTypeMana)
	local maxMana = UnitPowerMax("player", powerTypeMana)

	if maxMana == 0 then
		return 0
	end

	return (mana / maxMana) * 100
end

---Mana values can be secret, so they are never compared or used in arithmetic.
local function UpdateManaText(mana, maxMana)
	local centreText = container.ManaText
	local percentageText = container.ManaPercentage
	local valueText = container.ManaValue
	local mode = GetCVar("statusTextDisplay")

	centreText:SetText("")
	percentageText:SetText("")
	valueText:SetText("")

	if mode == "NUMERIC" then
		centreText:SetText(string.format("%s / %s", AbbreviateNumbers(mana), AbbreviateNumbers(maxMana)))
	elseif mode == "PERCENT" then
		centreText:SetText(string.format("%d%%", GetManaPercentage()))
	elseif mode == "BOTH" or db.TextEnabled or hovered then
		percentageText:SetText(string.format("%d%%", GetManaPercentage()))
		valueText:SetText(AbbreviateNumbers(mana))
	end
end

local function UpdateManaBar()
	local mana = UnitPower("player", powerTypeMana)
	local maxMana = UnitPowerMax("player", powerTypeMana)

	local manaBar = container.ManaBar

	manaBar:SetMinMaxValues(0, maxMana)
	manaBar:SetValue(mana)

	UpdateManaText(mana, maxMana)

	local type = UnitPowerType("player")
	local show = type ~= powerTypeMana and not (blizzardManaBar and blizzardManaBar:IsVisible())

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

local function OnBarEnter()
	hovered = true
	UpdateManaBar()
end

local function OnBarLeave()
	hovered = false
	UpdateManaBar()
end

local function GetFrameArt()
	local frameContainer = PlayerFrame and PlayerFrame.PlayerFrameContainer

	if frameContainer and frameContainer.AlternatePowerFrameTexture then
		return frameContainer
	end

	return nil
end

---Only textures change here, so a form shift in combat cannot be blocked.
local function SyncFrameArt()
	-- Vehicle and health-only art have no slot under the mana bar.
	if PlayerFrame.state == "vehicle" or UNIT_FRAME_SHOW_HEALTH_ONLY then
		return
	end

	local frameContainer = PlayerFrame.PlayerFrameContainer
	-- Blizzard's own alternate bar sits in the same slot and needs the same art.
	local alternate = container:IsShown() or PlayerFrame_GetAlternatePowerBar() ~= nil
	local art = alternate and alternateArt or playerArt
	local flash = frameContainer.FrameFlash
	local manaBarMask = PlayerFrame.manabar and PlayerFrame.manabar.ManaBarMask

	frameContainer.FrameTexture:SetShown(not alternate)
	frameContainer.AlternatePowerFrameTexture:SetShown(alternate)
	flash:SetAtlas(art.Flash, TextureKitConstants.UseAtlasSize)
	flash:SetPoint("CENTER", flash:GetParent(), "CENTER", art.FlashX, art.FlashY)

	if manaBarMask then
		manaBarMask:SetAtlas(art.ManaMask, TextureKitConstants.UseAtlasSize)
	end
end

local function InitFrameArt(manaBar)
	-- The mask Blizzard's alternate bar uses to round the fill into the slot.
	local mask = manaBar:CreateMaskTexture()
	mask:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", TextureKitConstants.UseAtlasSize)
	mask:SetPoint("TOPLEFT", manaBar, "TOPLEFT", -2, 3)
	manaBar:GetStatusBarTexture():AddMaskTexture(mask)

	container:SetScript("OnShow", SyncFrameArt)
	container:SetScript("OnHide", SyncFrameArt)

	-- Blizzard redraws the frame art on these, which would undo the swap.
	hooksecurefunc("PlayerFrame_ToPlayerArt", SyncFrameArt)
	hooksecurefunc("PlayerFrame_ToVehicleArt", SyncFrameArt)
end

local function CreateClassicBorderPiece(manaBar, left, right)
	local piece = manaBar:CreateTexture(nil, "OVERLAY", nil, -1)
	piece:SetTexture(classicBorderFile)
	piece:SetSize(16, 16)
	-- Flipped vertically, as Blizzard's classic alternate mana bar draws it.
	piece:SetTexCoord(left, right, 1, 0)

	return piece
end

local function InitClassicBorder(manaBar)
	local bg = manaBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)

	local middle = CreateClassicBorderPiece(manaBar, 0.125, 0.25)
	middle:SetPoint("TOPLEFT", manaBar, "TOPLEFT", 4, 0)
	middle:SetPoint("TOPRIGHT", manaBar, "TOPRIGHT", -4, 0)

	local left = CreateClassicBorderPiece(manaBar, 0, 0.125)
	left:SetPoint("RIGHT", middle, "LEFT")

	local right = CreateClassicBorderPiece(manaBar, 0.125, 0)
	right:SetPoint("LEFT", middle, "RIGHT")

	container.BorderLeft = left
	container.BorderMiddle = middle
	container.BorderRight = right
end

local function InitManaBar()
	container = CreateFrame("Frame", "MiniDruidManaContainer", PlayerFrame)

	local frameArt = GetFrameArt()

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
	elseif frameArt then
		-- retail, in the slot Blizzard's alternate power bar uses
		container:SetPoint("TOPLEFT", PlayerFrame.PlayerFrameContent.PlayerFrameContentMain, "TOPLEFT", 85, -73)
		container:SetSize(124, 9)
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

	local manaText = manaBar:CreateFontString(nil, "OVERLAY")
	manaText:SetFont(font.File, font.Size, font.Flags)
	manaText:SetPoint("CENTER", container, "CENTER", 0, 0)
	manaText:Show()

	local manaPercentage = manaBar:CreateFontString(nil, "OVERLAY")
	manaPercentage:SetFont(font.File, font.Size, font.Flags)
	manaPercentage:SetPoint("LEFT", container, "LEFT", leftInset, 0)
	manaPercentage:Show()

	local manaValue = manaBar:CreateFontString(nil, "OVERLAY")
	manaValue:SetFont(font.File, font.Size, font.Flags)
	manaValue:SetPoint("RIGHT", container, "RIGHT", -rightInset, 0)
	manaValue:Show()

	-- Hovering shows the text, like the player frame's own bars.
	manaBar:SetScript("OnEnter", OnBarEnter)
	manaBar:SetScript("OnLeave", OnBarLeave)
	manaBar:SetMouseMotionEnabled(true)
	manaBar:SetMouseClickEnabled(false)

	if frameArt then
		InitFrameArt(manaBar)
	else
		InitClassicBorder(manaBar)
	end

	if PlayerFrameBottomManagedFramesContainer then
		local point, relativeTo, relativeToPoint, xOffset, yOffset = PlayerFrameBottomManagedFramesContainer:GetPoint()
		PlayerFrameBottomManagedFramesContainer:ClearAllPoints()
		-- shift the combo points frame down a tad
		PlayerFrameBottomManagedFramesContainer:SetPoint(point, relativeTo, relativeToPoint, xOffset, yOffset - 5)
	end

	-- AlternatePowerBar on retail, PlayerFrameAlternateManaBar on Wrath, Cata, and Mists Classic.
	blizzardManaBar = AlternatePowerBar or PlayerFrameAlternateManaBar

	if blizzardManaBar then
		blizzardManaBar:HookScript("OnShow", UpdateManaBar)
		blizzardManaBar:HookScript("OnHide", UpdateManaBar)
	end

	container.ManaBar = manaBar
	container.ManaText = manaText
	container.ManaPercentage = manaPercentage
	container.ManaValue = manaValue

	UpdateManaBar()

	if frameArt then
		-- Showing an already shown container fires no OnShow, so the first sync is by hand.
		SyncFrameArt()
	end
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
	frame:RegisterEvent("CVAR_UPDATE")
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
