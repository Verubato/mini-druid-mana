local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
local verticalSpacing = 20
local db
---@class Db
local dbDefaults = {
	TextEnabled = false,
}
local M = {}
addon.Config = M

function M:Init()
	db = mini:GetSavedVars(dbDefaults)

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -verticalSpacing)
	title:SetText(string.format("%s - %s", addonName, version))

	local description = panel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetText("Shows a mana bar while in cat/bear/boomkin form.")

	local textEnabledChk = mini:Checkbox({
		Parent = panel,
		LabelText = "Show text",
		Tooltip = "Whether to show or hide the mana value and percentage text.",
		GetValue = function()
			return db.TextEnabled
		end,
		SetValue = function(enabled)
			db.TextEnabled = enabled
            addon:Update()
		end,
	})

	textEnabledChk:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -verticalSpacing)

	mini:RegisterSlashCommand(category, panel, {
		"/minidruidmana",
		"/minidm",
		"/mdm",
	})
end
