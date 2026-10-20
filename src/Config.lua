local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
local verticalSpacing = 20
local db
---@class Db
local dbDefaults = {
	TextEnabled = false,
	FiveSecondRuleEnabled = true,
}
---@class Config
local M = {}
addon.Config = M

function M:Init()
	-- A styled button clashes with the stock Blizzard art around it in the settings screen.
	mini:SetCustomStyling(true, { Button = false })

	db = mini:GetSavedVars(dbDefaults)

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local header = mini:PanelHeader({
		Parent = panel,
		Description = "Shows a mana bar while in cat/bear/boomkin form.",
		Divider = true,
	})

	local textEnabledChk = mini:Checkbox({
		Parent = panel,
		LabelText = "Always show text",
		Tooltip = "Keep the mana percentage and value visible when Interface > Display > Status Text is set to None. Otherwise the text follows that setting, and shows on mouseover when it is None.",
		GetValue = function()
			return db.TextEnabled
		end,
		SetValue = function(enabled)
			db.TextEnabled = enabled
            addon:Update()
		end,
	})

	textEnabledChk:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", 0, -verticalSpacing)

	if addon:HasFiveSecondRule() then
		local fiveSecondRuleChk = mini:Checkbox({
			Parent = panel,
			LabelText = "Show five second rule",
			Tooltip = "Sweep a marker across the mana bar for five seconds after a spell that costs mana, so you can see when mana regeneration resumes.",
			GetValue = function()
				return db.FiveSecondRuleEnabled
			end,
			SetValue = function(enabled)
				db.FiveSecondRuleEnabled = enabled
				addon:Update()
			end,
		})

		fiveSecondRuleChk:SetPoint("TOPLEFT", textEnabledChk, "BOTTOMLEFT", 0, -verticalSpacing)
	end

	mini:RegisterSlashCommand(category, panel, {
		"/minidruidmana",
		"/minidm",
		"/mdm",
	})
end
