-- Drives the mana bar through the mocked client's event and unit APIs.
--
-- WowMock.SetPlayerClass hardcodes the class index it reports to 1 regardless of token, so it
-- can never answer the druid class id (11) this addon gates on. LoadAsDruid works around that by
-- overriding UnitClass locally, after the files load but before login fires Init.
--
-- CurveConstants is a real WoW global the mock does not model at all. LoadAsDruid primes it
-- unconditionally because Login's first draw can reach it before a test's own before_each does.

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---@param beforeLogin fun()? runs after the files load and before Init builds the bar
local function LoadAsDruid(beforeLogin)
	local context = harness.Load("MiniDruidMana")

	_G.UnitClass = function(unit)
		if unit == "player" then
			return "Druid", "DRUID", 11
		end

		return nil, nil, nil
	end

	_G.CurveConstants = { ScaleTo100 = {} }

	if beforeLogin then
		beforeLogin()
	end

	context.LoginResult = harness.Login(context)

	return context
end

local function Container()
	return _G.MiniDruidManaContainer
end

local function SetPowerType(powerType)
	_G.UnitPowerType = function()
		return powerType
	end

	WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")
end

-- The mock has no frame art, so this builds the parts PlayerFrame_ToPlayerArt and
-- PlayerFrame_ToVehicleArt touch.
local function InstallRetailArt()
	local playerFrame = _G.PlayerFrame
	local art = _G.CreateFrame("Frame", nil, playerFrame)

	art.FrameTexture = art:CreateTexture()
	art.AlternatePowerFrameTexture = art:CreateTexture()
	art.AlternatePowerFrameTexture:Hide()
	art.FrameFlash = art:CreateTexture()
	playerFrame.PlayerFrameContainer = art
	playerFrame.manabar.ManaBarMask = playerFrame.manabar:CreateMaskTexture()
	playerFrame.state = "player"

	_G.TextureKitConstants = { UseAtlasSize = true }
	_G.PlayerFrame_GetAlternatePowerBar = function()
		return playerFrame.activeAlternatePowerBar
	end
	_G.PlayerFrame_ToPlayerArt = function()
		playerFrame.state = "player"
		art.FrameTexture:Show()
		art.AlternatePowerFrameTexture:Hide()
		art.FrameFlash:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-InCombat")
	end
	_G.PlayerFrame_ToVehicleArt = function()
		playerFrame.state = "vehicle"
		art.FrameTexture:Hide()
		art.AlternatePowerFrameTexture:Hide()
		art.FrameFlash:SetAtlas("vehicle")
	end
end

fw.describe("MiniDruidMana - GetManaPercentage", function()
	fw.before_each(function()
		LoadAsDruid()
		_G.MiniDruidManaDB.TextEnabled = true
		_G.CurveConstants = { ScaleTo100 = {} }
	end)

	fw.it("reads the percentage through UnitPowerPercent when it is available", function()
		_G.UnitPowerPercent = function()
			return 73
		end

		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.eq(Container().ManaPercentage:GetText(), "73%", "the curve's own answer is used directly")
	end)

	fw.it("falls back to a manual division when UnitPowerPercent is absent from the client", function()
		_G.UnitPowerPercent = nil
		_G.UnitPower = function()
			return 30
		end
		_G.UnitPowerMax = function()
			return 60
		end

		fw.no_error(function()
			WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")
		end, "the manual fallback path")

		fw.eq(Container().ManaPercentage:GetText(), "50%", "30 of 60 is 50%, computed by hand")
	end)

	fw.it("shows 0% when the fallback's max power is zero", function()
		_G.UnitPowerPercent = nil
		_G.UnitPower = function()
			return 30
		end
		_G.UnitPowerMax = function()
			return 0
		end

		fw.no_error(function()
			WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")
		end, "a zero max in the fallback path")

		fw.eq(Container().ManaPercentage:GetText(), "0%", "zero max is guarded to 0%")
	end)
end)

fw.describe("MiniDruidMana - form visibility", function()
	local manaType

	fw.before_each(function()
		LoadAsDruid()
		-- Read back after load: the addon captured this exact value into its own upvalue at
		-- file scope, and the mock's auto-vivifying Enum caches it, so this is the same number.
		manaType = _G.Enum.PowerType.Mana
		-- Install() preserves saved variables across a load, modelling a /reload, so a value an
		-- earlier describe block wrote survives into this one unless reset here.
		_G.MiniDruidManaDB.TextEnabled = false
	end)

	fw.it("hides the bar once the current power type is mana", function()
		_G.UnitPowerType = function()
			return manaType
		end

		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.falsy(Container():IsShown(), "hidden while the player is in mana form")
	end)

	fw.it("shows the bar once the current power type is not mana", function()
		_G.UnitPowerType = function()
			return manaType + 1
		end

		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.truthy(Container():IsShown(), "shown once out of mana form")
	end)

	fw.it("re-evaluates visibility on UPDATE_SHAPESHIFT_FORM too", function()
		_G.UnitPowerType = function()
			return manaType + 1
		end

		WowMock.FireEvent("UPDATE_SHAPESHIFT_FORM")

		fw.truthy(Container():IsShown(), "a form change alone drives the same visibility check")

		_G.UnitPowerType = function()
			return manaType
		end

		WowMock.FireEvent("UPDATE_SHAPESHIFT_FORM")

		fw.falsy(Container():IsShown(), "and hides again once the form change means mana")
	end)
end)

fw.describe("MiniDruidMana - power update routing", function()
	local manaType

	fw.before_each(function()
		LoadAsDruid()
		manaType = _G.Enum.PowerType.Mana
		_G.MiniDruidManaDB.TextEnabled = false
		_G.UnitPowerType = function()
			return manaType + 1
		end
		_G.UnitPower = function()
			return 40
		end
	end)

	fw.it("ignores UNIT_POWER_UPDATE for a foreign power type", function()
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player") -- establishes a baseline value of 40

		_G.UnitPower = function()
			return 99
		end

		WowMock.FireEvent("UNIT_POWER_UPDATE", "player", "RAGE")

		fw.eq(Container().ManaBar:GetValue(), 40, "no redraw for a power type that is not mana")
	end)

	fw.it("redraws on UNIT_POWER_UPDATE when the power type is mana", function()
		WowMock.FireEvent("UNIT_POWER_UPDATE", "player", "MANA")

		fw.eq(Container().ManaBar:GetValue(), 40, "redrew for its own power type")
	end)

	fw.it("ignores UNIT_POWER_FREQUENT for a foreign power type too", function()
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		_G.UnitPower = function()
			return 12
		end

		WowMock.FireEvent("UNIT_POWER_FREQUENT", "player", "ENERGY")

		fw.eq(Container().ManaBar:GetValue(), 40, "no redraw for a power type that is not mana")
	end)
end)

fw.describe("MiniDruidMana - text toggle", function()
	local manaType

	fw.before_each(function()
		LoadAsDruid()
		manaType = _G.Enum.PowerType.Mana
		_G.UnitPowerType = function()
			return manaType + 1
		end
		_G.CurveConstants = { ScaleTo100 = {} }
		_G.UnitPowerPercent = function()
			return 55
		end
		_G.UnitPower = function()
			return 40
		end
	end)

	fw.it("shows the percentage and value text once TextEnabled is true", function()
		_G.MiniDruidManaDB.TextEnabled = true

		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.eq(Container().ManaPercentage:GetText(), "55%", "percentage text populated")
		fw.eq(Container().ManaValue:GetText(), "40", "value text populated")
	end)

	fw.it("clears both text fields once TextEnabled is false", function()
		_G.MiniDruidManaDB.TextEnabled = true
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.neq(Container().ManaPercentage:GetText(), "", "populated first")

		_G.MiniDruidManaDB.TextEnabled = false
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		fw.eq(Container().ManaPercentage:GetText(), "", "percentage cleared")
		fw.eq(Container().ManaValue:GetText(), "", "value cleared")
	end)
end)

fw.describe("MiniDruidMana - status text setting", function()
	local manaType
	local mode

	fw.before_each(function()
		LoadAsDruid()
		manaType = _G.Enum.PowerType.Mana
		mode = "NONE"
		_G.MiniDruidManaDB.TextEnabled = false
		_G.GetCVar = function(name)
			if name == "statusTextDisplay" then
				return mode
			end

			return "0"
		end
		_G.UnitPowerType = function()
			return manaType + 1
		end
		_G.UnitPowerPercent = function()
			return 50
		end
		_G.UnitPower = function()
			return 4000
		end
		_G.UnitPowerMax = function()
			return 8000
		end
	end)

	local function Texts()
		return Container().ManaText:GetText(), Container().ManaPercentage:GetText(), Container().ManaValue:GetText()
	end

	fw.it("shows value over max in the centre for NUMERIC", function()
		mode = "NUMERIC"
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		local centre, left, right = Texts()

		fw.eq(centre, "4.0K / 8.0K", "abbreviated value and max")
		fw.eq(left .. right, "", "sides empty")
	end)

	fw.it("shows the percentage in the centre for PERCENT", function()
		mode = "PERCENT"
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		local centre, left, right = Texts()

		fw.eq(centre, "50%", "percentage")
		fw.eq(left .. right, "", "sides empty")
	end)

	fw.it("shows the percentage left and the value right for BOTH", function()
		mode = "BOTH"
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		local centre, left, right = Texts()

		fw.eq(centre, "", "centre empty")
		fw.eq(left, "50%", "percentage on the left")
		fw.eq(right, "4.0K", "value on the right")
	end)

	fw.it("shows nothing for NONE", function()
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		local centre, left, right = Texts()

		fw.eq(centre .. left .. right, "", "all empty")
	end)

	fw.it("shows the BOTH layout for NONE while Always show text is on", function()
		_G.MiniDruidManaDB.TextEnabled = true
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		local centre, left, right = Texts()

		fw.eq(centre, "", "centre empty")
		fw.eq(left, "50%", "percentage on the left")
		fw.eq(right, "4.0K", "value on the right")
	end)

	fw.it("shows the text for NONE only while the bar is hovered", function()
		local manaBar = Container().ManaBar

		manaBar:GetScript("OnEnter")(manaBar)

		local _, left, right = Texts()

		fw.eq(left, "50%", "percentage while hovered")
		fw.eq(right, "4.0K", "value while hovered")

		manaBar:GetScript("OnLeave")(manaBar)

		local centre
		centre, left, right = Texts()

		fw.eq(centre .. left .. right, "", "cleared once the mouse leaves")
	end)

	fw.it("redraws when the setting changes", function()
		WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")

		mode = "PERCENT"
		WowMock.FireEvent("CVAR_UPDATE", "statusTextDisplay", "PERCENT")

		fw.eq(Container().ManaText:GetText(), "50%", "picked up without a power event")
	end)
end)

fw.describe("MiniDruidMana - secret mana values", function()
	local manaType

	fw.before_each(function()
		LoadAsDruid()
		manaType = _G.Enum.PowerType.Mana
		_G.MiniDruidManaDB.TextEnabled = false
		_G.UnitPowerType = function()
			return manaType + 1
		end
		_G.UnitPowerPercent = function()
			return WowMock.MakeSecret(50)
		end
		_G.UnitPower = function()
			return WowMock.MakeSecret(4000)
		end
		_G.UnitPowerMax = function()
			return WowMock.MakeSecret(8000)
		end
		-- The client's own AbbreviateNumbers accepts a secret and hands one back.
		_G.AbbreviateNumbers = function(value)
			return value
		end
	end)

	for _, mode in ipairs({ "NUMERIC", "PERCENT", "BOTH", "NONE" }) do
		fw.it("never compares or does arithmetic on a secret in " .. mode .. " mode", function()
			_G.MiniDruidManaDB.TextEnabled = true
			_G.GetCVar = function(name)
				return name == "statusTextDisplay" and mode or "0"
			end

			fw.no_error(function()
				WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")
			end, "a full redraw with secret mana")

			local text = Container().ManaPercentage:GetText()

			if mode == "NUMERIC" or mode == "PERCENT" then
				text = Container().ManaText:GetText()
			end

			fw.truthy(issecretvalue(text), "the secret reached the font string untouched")
		end)
	end
end)

fw.describe("MiniDruidMana - retail frame art", function()
	local manaType
	local art

	fw.before_each(function()
		LoadAsDruid(InstallRetailArt)
		manaType = _G.Enum.PowerType.Mana
		art = _G.PlayerFrame.PlayerFrameContainer
		_G.MiniDruidManaDB.TextEnabled = false
	end)

	local function AssertAlternateArt(message)
		fw.falsy(art.FrameTexture:IsShown(), message .. ": plain frame hidden")
		fw.truthy(art.AlternatePowerFrameTexture:IsShown(), message .. ": alternate frame shown")
		fw.eq(art.FrameFlash:GetAtlas(), "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource-InCombat", message .. ": flash")
		fw.eq(_G.PlayerFrame.manabar.ManaBarMask:GetAtlas(), "Unit_BarMask", message .. ": mana mask")
	end

	local function AssertPlayerArt(message)
		fw.truthy(art.FrameTexture:IsShown(), message .. ": plain frame shown")
		fw.falsy(art.AlternatePowerFrameTexture:IsShown(), message .. ": alternate frame hidden")
		fw.eq(art.FrameFlash:GetAtlas(), "UI-HUD-UnitFrame-Player-PortraitOn-InCombat", message .. ": flash")
		fw.eq(
			_G.PlayerFrame.manabar.ManaBarMask:GetAtlas(),
			"UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask",
			message .. ": mana mask"
		)
	end

	fw.it("sits in the alternate power bar slot with Blizzard's mask on the fill", function()
		local main = _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
		local point, relativeTo, relativePoint, x, y = Container():GetPoint()
		local width, height = Container():GetSize()
		local masks = Container().ManaBar:GetStatusBarTexture().__masks

		fw.eq(point .. relativePoint, "TOPLEFTTOPLEFT", "top left to top left")
		fw.eq(relativeTo, main, "anchored to the frame content")
		fw.eq(x, 85, "slot x")
		fw.eq(y, -73, "slot y")
		fw.eq(width, 124, "slot width")
		fw.eq(height, 9, "slot height")
		fw.eq(masks[1]:GetAtlas(), "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", "fill masked")
	end)

	fw.it("swaps to the alternate frame art while the bar shows and back when it hides", function()
		SetPowerType(manaType + 1)

		AssertAlternateArt("bar shown")

		SetPowerType(manaType)

		AssertPlayerArt("bar hidden")

		local _, _, _, x, y = art.FrameFlash:GetPoint(#art.FrameFlash.__points)

		fw.eq(x, -1.5, "flash x put back")
		fw.eq(y, 1, "flash y put back")
	end)

	fw.it("swaps the art at login when the bar starts out shown", function()
		LoadAsDruid(function()
			InstallRetailArt()
			_G.UnitPowerType = function()
				return manaType + 1
			end
		end)
		art = _G.PlayerFrame.PlayerFrameContainer

		AssertAlternateArt("straight after login")
	end)

	fw.it("keeps the alternate art while Blizzard's own alternate bar is up", function()
		_G.PlayerFrame.activeAlternatePowerBar = {}

		SetPowerType(manaType + 1)
		SetPowerType(manaType)

		AssertAlternateArt("only Blizzard's bar left")
	end)

	fw.it("re-applies the swap after Blizzard redraws the player art", function()
		SetPowerType(manaType + 1)

		_G.PlayerFrame_ToPlayerArt(_G.PlayerFrame)

		AssertAlternateArt("after PlayerFrame_ToPlayerArt")
	end)

	fw.it("leaves vehicle art alone", function()
		SetPowerType(manaType + 1)

		_G.PlayerFrame_ToVehicleArt(_G.PlayerFrame)
		SetPowerType(manaType)
		SetPowerType(manaType + 1)

		fw.falsy(art.FrameTexture:IsShown(), "plain frame stays hidden")
		fw.falsy(art.AlternatePowerFrameTexture:IsShown(), "alternate frame stays hidden")
		fw.eq(art.FrameFlash:GetAtlas(), "vehicle", "vehicle flash kept")
	end)

	fw.it("only hooks the two art functions", function()
		for _, name in ipairs(WowMock.Hooks) do
			fw.truthy(name:find("^PlayerFrame_To") ~= nil, "unexpected hook " .. name)
		end

		fw.eq(#WowMock.Hooks, 2, "only the two art hooks")
	end)
end)

fw.describe("MiniDruidMana - classic border", function()
	fw.before_each(function()
		LoadAsDruid(function()
			_G.PlayerFrameManaBar = _G.CreateFrame("StatusBar", nil, _G.PlayerFrame)
		end)
	end)

	local function TexCoord(texture)
		local left, top, _, bottom, right = texture:GetTexCoord()

		return { left, right, top, bottom }
	end

	fw.it("draws the group indicator border flipped vertically, with caps on each end", function()
		local file = "Interface\\CharacterFrame\\UI-CharacterFrame-GroupIndicator"

		for _, key in ipairs({ "BorderLeft", "BorderMiddle", "BorderRight" }) do
			fw.eq(Container()[key]:GetTexture(), file, key .. " texture")
		end

		fw.eq(table.concat(TexCoord(Container().BorderMiddle), ","), "0.125,0.25,1,0", "middle")
		fw.eq(table.concat(TexCoord(Container().BorderLeft), ","), "0,0.125,1,0", "left cap")
		fw.eq(table.concat(TexCoord(Container().BorderRight), ","), "0.125,0,1,0", "right cap mirrored")
	end)

	fw.it("adds no frame art hooks without Blizzard's alternate frame art", function()
		fw.eq(#WowMock.Hooks, 0, "no hooks at all")
	end)
end)

fw.describe("MiniDruidMana - Blizzard's own alternate mana bar", function()
	local manaType
	local blizzardBar

	fw.describe("retail", function()
		local art

		fw.before_each(function()
			LoadAsDruid(function()
				InstallRetailArt()
				_G.AlternatePowerBar = _G.CreateFrame("StatusBar", nil, _G.PlayerFrame)
				_G.AlternatePowerBar:Hide()
			end)
			manaType = _G.Enum.PowerType.Mana
			blizzardBar = _G.AlternatePowerBar
			art = _G.PlayerFrame.PlayerFrameContainer
			SetPowerType(manaType + 1)
		end)

		-- Blizzard sets the active bar before the art redraw.
		local function EnableBlizzardBar()
			_G.PlayerFrame.activeAlternatePowerBar = blizzardBar
			_G.PlayerFrame_ToPlayerArt(_G.PlayerFrame)
			blizzardBar:Show()
		end

		local function DisableBlizzardBar()
			_G.PlayerFrame.activeAlternatePowerBar = nil
			_G.PlayerFrame_ToPlayerArt(_G.PlayerFrame)
			blizzardBar:Hide()
		end

		fw.it("ignores Blizzard's bar while its parent area is hidden", function()
			local area = _G.CreateFrame("Frame", nil, _G.PlayerFrame)
			area:Hide()
			blizzardBar:SetParent(area)
			blizzardBar:Show()
			SetPowerType(manaType + 1)

			fw.truthy(Container():IsShown(), "ours shown")
		end)

		fw.it("hides ours while Blizzard's bar shows and keeps the alternate art", function()
			EnableBlizzardBar()

			fw.falsy(Container():IsShown(), "ours hidden")
			fw.falsy(art.FrameTexture:IsShown(), "plain frame hidden")
			fw.truthy(art.AlternatePowerFrameTexture:IsShown(), "alternate frame kept")
		end)

		fw.it("stays hidden through power updates while Blizzard's bar shows", function()
			EnableBlizzardBar()
			SetPowerType(manaType + 1)

			fw.falsy(Container():IsShown(), "still hidden")
		end)

		fw.it("brings ours back with the alternate art once Blizzard's bar hides", function()
			EnableBlizzardBar()

			fw.falsy(Container():IsShown(), "ours hidden first")

			DisableBlizzardBar()

			fw.truthy(Container():IsShown(), "ours back")
			fw.falsy(art.FrameTexture:IsShown(), "plain frame hidden")
			fw.truthy(art.AlternatePowerFrameTexture:IsShown(), "alternate frame shown for ours")
		end)
	end)

	fw.describe("classic", function()
		fw.before_each(function()
			LoadAsDruid(function()
				_G.PlayerFrameManaBar = _G.CreateFrame("StatusBar", nil, _G.PlayerFrame)
				_G.PlayerFrameAlternateManaBar = _G.CreateFrame("StatusBar", nil, _G.PlayerFrame)
				_G.PlayerFrameAlternateManaBar:Hide()
			end)
			manaType = _G.Enum.PowerType.Mana
			blizzardBar = _G.PlayerFrameAlternateManaBar
			SetPowerType(manaType + 1)
		end)

		fw.it("hides ours while Blizzard's bar shows and brings it back after", function()
			fw.truthy(Container():IsShown(), "ours shown before")

			blizzardBar:Show()

			fw.falsy(Container():IsShown(), "ours hidden")

			blizzardBar:Hide()

			fw.truthy(Container():IsShown(), "ours back")
		end)

		fw.it("keeps ours hidden when Blizzard's bar hides in a mana form", function()
			blizzardBar:Show()
			_G.UnitPowerType = function()
				return manaType
			end
			blizzardBar:Hide()

			fw.falsy(Container():IsShown(), "the form rule still applies")
		end)
	end)
end)

fw.describe("MiniDruidMana - non-druid login", function()
	fw.it("never creates the mana bar container for another class", function()
		-- The mock's default player class is a Warrior, which is exactly the case this proves:
		-- no class override needed to land outside the druid gate.
		harness.Run("MiniDruidMana")

		fw.is_nil(Container(), "InitManaBar never ran: Init returned before reaching it")
	end)

	fw.it("does not error when a power event arrives with no druid setup", function()
		harness.Run("MiniDruidMana")

		fw.no_error(function()
			WowMock.FireEvent("UNIT_DISPLAYPOWER", "player")
			WowMock.FireEvent("UPDATE_SHAPESHIFT_FORM")
		end, "power events with the druid frame never registered")
	end)
end)

fw.describe("MiniDruidMana - five second rule", function()
	local mainline = _G.WOW_PROJECT_ID

	local function CastWithCost(cost)
		_G.C_Spell.GetSpellPowerCost = function(spellId)
			if spellId == 774 then
				return { { type = _G.Enum.PowerType.Mana, cost = cost } }
			end
		end

		return WowMock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 774)
	end

	local function Marker()
		for i = #WowMock.Frames, 1, -1 do
			if WowMock.Frames[i].Marker then
				return WowMock.Frames[i]
			end
		end
	end

	fw.before_each(function()
		_G.WOW_PROJECT_ID = mainline
		_G.WOW_PROJECT_CAMELOT = nil
		_G.PlayerFrameManaBar = nil
	end)

	fw.it("shows the countdown on the bar after a mana spending cast on Classic", function()
		LoadAsDruid(function()
			_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CLASSIC
		end)
		SetPowerType(_G.Enum.PowerType.Mana + 1)

		CastWithCost(50)

		local countdown = Marker()
		fw.truthy(countdown:IsShown(), "the marker is up for the five second window")
		fw.eq(countdown.Text:GetText(), "5.0", "the full window remains straight after the cast")
	end)

	fw.it("ignores a cast that costs no mana", function()
		LoadAsDruid(function()
			_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CLASSIC
		end)
		SetPowerType(_G.Enum.PowerType.Mana + 1)

		CastWithCost(0)

		fw.falsy(Marker():IsShown(), "a free cast starts no window")
	end)

	fw.it("hides the countdown once five seconds have passed", function()
		LoadAsDruid(function()
			_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CLASSIC
		end)
		SetPowerType(_G.Enum.PowerType.Mana + 1)
		CastWithCost(50)
		local countdown = Marker()

		WowMock.AdvanceTime(5.1)
		WowMock.RunOnUpdate(0.1)

		fw.falsy(countdown:IsShown(), "the window is over")
	end)

	fw.it("keeps the countdown on screen after leaving a form mid window", function()
		LoadAsDruid(function()
			_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CLASSIC
		end)
		_G.PlayerFrameManaBar = CreateFrame("StatusBar")
		SetPowerType(_G.Enum.PowerType.Mana + 1)
		CastWithCost(50)
		local countdown = Marker()

		SetPowerType(_G.Enum.PowerType.Mana)
		WowMock.AdvanceTime(1)
		WowMock.RunOnUpdate(0.1)

		fw.eq(countdown:GetParent(), _G.PlayerFrameManaBar, "the marker moves to the player mana bar")
		fw.truthy(countdown:IsShown(), "the marker is still up")
	end)

	fw.it("listens for casts on the Camelot client", function()
		LoadAsDruid(function()
			_G.WOW_PROJECT_CAMELOT = 18
			_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CAMELOT
		end)

		fw.eq(CastWithCost(50), 1, "one frame registered for UNIT_SPELLCAST_SUCCEEDED")
	end)

	fw.it("puts the countdown on the newer player frame's mana bar in caster form", function()
		LoadAsDruid(function()
			_G.WOW_PROJECT_CAMELOT = 18
			_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CAMELOT
		end)
		SetPowerType(_G.Enum.PowerType.Mana)

		CastWithCost(50)

		fw.eq(Marker():GetParent(), _G.PlayerFrame.manabar, "the marker sits on PlayerFrame.manabar")
	end)

	fw.it("does not listen for casts on retail", function()
		LoadAsDruid()

		fw.eq(CastWithCost(50), 0, "no frame registered for UNIT_SPELLCAST_SUCCEEDED")
	end)

	fw.it("does not listen for casts on Cataclysm Classic", function()
		LoadAsDruid(function()
			_G.WOW_PROJECT_ID = _G.WOW_PROJECT_CATACLYSM_CLASSIC
		end)

		fw.eq(CastWithCost(50), 0, "no frame registered for UNIT_SPELLCAST_SUCCEEDED")
	end)
end)
