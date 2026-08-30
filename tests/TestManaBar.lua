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

local function LoadAsDruid()
	local context = harness.Load("MiniDruidMana")

	_G.UnitClass = function(unit)
		if unit == "player" then
			return "Druid", "DRUID", 11
		end

		return nil, nil, nil
	end

	-- Login below fires the first UpdateManaBar draw. If a prior describe block left the
	-- preserved TextEnabled true, that draw reaches GetManaPercentage before this file's own
	-- before_each gets a chance to set CurveConstants, so it is primed here unconditionally.
	_G.CurveConstants = { ScaleTo100 = {} }

	context.LoginResult = harness.Login(context)

	return context
end

local function Container()
	return _G.MiniDruidManaContainer
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

	-- The fallback branch never guards a zero max, so (mana / 0) * 100 formats as garbage.
	fw.xfail("would show 0% if the fallback's max power guard existed", function()
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

		fw.eq(Container().ManaPercentage:GetText(), "0%", "BUG: unguarded division by zero renders as garbage, not 0%")
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
