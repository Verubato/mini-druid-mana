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

	local header = mini:PanelHeader({
		Parent = panel,
		Description = "Shows a mana bar while in cat/bear/boomkin form.",
		Y = -verticalSpacing,
	})

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

	textEnabledChk:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", 0, -verticalSpacing)

	mini:RegisterSlashCommand(category, panel, {
		"/minidruidmana",
		"/minidm",
		"/mdm",
	})
end
