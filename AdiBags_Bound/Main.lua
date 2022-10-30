--[[

The MIT License (MIT)

Copyright (c) 2022 Lucas Vienna (Avyiel), Spanky, Kevin (kevin@outroot.com)
Copyright (c) 2021 Lars Norberg

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
	
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]]
--[[
	Many thanks to Lars Norberg, aka GoldpawForever. This is largely inspired by his
	BlizzardBags addons: https://github.com/GoldpawsStuff/BlizzardBags_BoE
	and partially based on his template: https://github.com/GoldpawsStuff/AddonTemplate
--]]

-- Retrive addon folder name, and our local, private namespace.
local Addon, Private = ...

-- AdiBags namespace
-----------------------------------------------------------
local AdiBags = LibStub("AceAddon-3.0"):GetAddon("AdiBags")

-- Lua API
-----------------------------------------------------------
local _G = _G
local string_find = string.find
local string_split = string.split
local tonumber = tonumber

-- WoW API
-----------------------------------------------------------
local CreateFrame = _G.CreateFrame
local GetLocale = _G.GetLocale
local GetItemInfo = _G.GetItemInfo
local GetBuildInfo = _G.GetBuildInfo
local GetAddOnInfo = _G.GetAddOnInfo
local GetNumAddOns = _G.GetNumAddOns
local C_Item_GetItemInventoryTypeByID = _G.C_Item.GetItemInventoryTypeByID

-- WoW10 API
-----------------------------------------------------------
local C_TooltipInfo_GetBagItem = C_TooltipInfo and C_TooltipInfo.GetBagItem

-- WoW Strings
-----------------------------------------------------------
local S_ITEM_BOP = ITEM_SOULBOUND
local S_ITEM_BOA = ITEM_ACCOUNTBOUND
local S_ITEM_BOA2 = ITEM_BNETACCOUNTBOUND
local S_ITEM_BOA3 = ITEM_BIND_TO_BNETACCOUNT
local S_ITEM_BOE = ITEM_BIND_ON_EQUIP

-- WoW Numbers
-----------------------------------------------------------
local N_BANK_CONTAINER = BANK_CONTAINER

-- Constants
-----------------------------------------------------------
local S_BOP = "BoP"
local S_BOA = "BoA"
local S_BOE = "BoE"

-- Localization system
-----------------------------------------------------------
-- Do not modify the function,
-- just the locales in the table below!
local L = Private.L or (function(tbl, defaultLocale)
	local gameLocale = GetLocale() -- The locale currently used by the game client.
	local L = tbl[gameLocale] or tbl[defaultLocale] -- Get the localization for the current locale, or use your default.
	-- Replace the boolean 'true' with the key,
	-- to simplify locale creation and reduce space needed.
	for i in pairs(L) do
		if (L[i] == true) then
			L[i] = i
		end
	end
	-- If the game client is in another locale than your default,
	-- fill in any missing localization in the client's locale
	-- with entries from your default locale.
	if (gameLocale ~= defaultLocale) then
		for i, msg in pairs(tbl[defaultLocale]) do
			if (not L[i]) then
				-- Replace the boolean 'true' with the key,
				-- to simplify locale creation and reduce space needed.
				L[i] = (msg == true) and i or msg
			end
		end
	end
	return L
end)({
	-- ENTER YOUR LOCALIZATION HERE!
	-----------------------------------------------------------
	-- * Note that you MUST include a full table for your primary/default locale!
	-- * Entries where the value (to the right) is the boolean 'true',
	--   will use the key (to the left) as the value instead!
	["enUS"] = {
		["Bound"] = true, -- uiName
		["Put BoE and BoA items in their own sections."] = true, --uiDesc

		-- Options
		["Enable BoE"] = true,
		["Check this if you want a section for BoE items."] = true,
		["Enable BoA"] = true,
		["Check this if you want a section for BoA items."] = true,
		["Soulbound"] = true,
		["Enable Soulbound"] = true,
		["Check this if you want a section for BoP items."] = true,
		["Only Equipable"] = true,
		["Only filter equipable soulbound items."] = true,

		-- Categories
		[S_BOA] = "BoA",
		[S_BOE] = "BoE",
		[S_BOP] = "Soulbound",
	},
	["deDE"] = {},
	["esES"] = {},
	["esMX"] = {},
	["frFR"] = {},
	["itIT"] = {},
	["koKR"] = {},
	["ptPT"] = {},
	["ruRU"] = {},
	["zhCN"] = {},
	["zhTW"] = {}

	-- The primary/default locale of your addon.
	-- * You should change this code to your default locale.
	-- * Note that you MUST include a full table for your primary/default locale!
}, "enUS")

--------------------------------------------------------------------------------
-- Filter Setup
--------------------------------------------------------------------------------

-- Register our filter with AdiBags
local filter = AdiBags:RegisterFilter("Bound", 70, "ABEvent-1.0")
filter.uiName = L["Bound"]
filter.uiDesc = L["Put BoE and BoA items in their own sections."]

function filter:OnInitialize()
	-- Register the settings namespace
	self.db = AdiBags.db:RegisterNamespace(self.filterName, {
		profile = {
			enableBoE = true,
			enableBoA = true,
			enableBoP = false,
			onlyEquipableBoP = true,
		},
	})
end

-- Setup options panel
function filter:GetOptions()
	return {
		enableBoE = {
			name = L["Enable BoE"],
			desc = L["Check this if you want a section for BoE items."],
			type = "toggle",
			width = "double",
			order = 10,
		},
		enableBoA = {
			name = L["Enable BoA"],
			desc = L["Check this if you want a section for BoA items."],
			type = "toggle",
			width = "double",
			order = 20,
		},
		bound = {
			name = L["Soulbound"],
			desc = "Soulbound stuff",
			type = "group",
			inline = true,
			args = {
				enableBoP = {
					name = L["Enable Soulbound"],
					desc = L["Check this if you want a section for BoP items."],
					type = "toggle",
					order = 10,
				},
				onlyEquipableBoP = {
					name = L["Only Equipable"],
					desc = L["Only filter equipable soulbound items."],
					type = "toggle",
					order = 20,
				},
			},
		},
	}, AdiBags:GetOptionHandler(self, true, function() return self:Update() end)
end

function filter:Update()
	-- Notify myself that the filtering options have changed
	self:SendMessage("AdiBags_FiltersChanged")
end

function filter:OnEnable()
	AdiBags:UpdateFilters()
end

function filter:OnDisable()
	AdiBags:UpdateFilters()
end

--------------------------------------------------------------------------------
-- Actual filter - with a cache
--------------------------------------------------------------------------------

-- Tooltip used for scanning.
-- Let's keep this name for all scanner addons.
local _SCANNER = "AVY_ScannerTooltip"
local Scanner
if not Private.WoW10 then
	-- This is not needed on WoW10, since we can use C_TooltipInfo.GetBagItem
	Scanner = _G[_SCANNER] or CreateFrame("GameTooltip", _SCANNER, WorldFrame, "GameTooltipTemplate")
end

-- Cache of information objects,
-- globally available so addons can share it.
local Cache = AVY_ItemBindInfoCache or {}
AVY_ItemBindInfoCache = Cache

function filter:Filter(slotData)
	local bag, slot, link, quality, itemId = slotData.bag, slotData.slot, slotData.link, slotData.quality, slotData.itemId

	if (Cache[itemId]) then
		return self:GetCategoryLabel(Cache[itemId], itemId)
	end

	if (link) then
		local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(link)

		-- Only parse items that are Common and above, and are of type BoP, BoE, and BoU
		if (quality and quality >= 1) and (bindType > 0 and bindType < 4) then

			local category = self:GetItemCategory(bag, slot)
			Cache[itemId] = category

			return self:GetCategoryLabel(category, itemId)
		end
	end
end

function filter:GetItemCategory(bag, slot)
	local category = nil

	local function GetBindType(msg)
		if (msg) then
			if (string_find(msg, S_ITEM_BOP)) then
				return S_BOP
			elseif (string_find(msg, S_ITEM_BOA) or string_find(msg, S_ITEM_BOA2) or string_find(msg, S_ITEM_BOA3)) then
				return S_BOA
			elseif (string_find(msg, S_ITEM_BOE)) then
				return S_BOE
			end
		end
	end

	if (Private.WoW10) then
		-- New API in WoW10 means we don't need an actual frame for the tooltip
		-- https://wowpedia.fandom.com/wiki/Patch_10.0.2/API_changes#Tooltip_Changes
		Scanner = C_TooltipInfo_GetBagItem(bag, slot)
		for i = 2, 6 do
			local line = Scanner.lines[i]
			if (not line) then
				break
			end
			local bind = GetBindType(line.leftText)
			if (bind) then
				category = bind
				break
			end
		end
	else
		Scanner.owner = self
		Scanner.bag = bag
		Scanner.slot = slot
		Scanner:ClearLines()
		Scanner:SetOwner(UIParent, "ANCHOR_NONE")
		if bag == N_BANK_CONTAINER then
			Scanner:SetInventoryItem("player", BankButtonIDToInvSlotID(slot, nil))
		else
			Scanner:SetBagItem(bag, slot)
		end
		for i = 2, 6 do
			local line = _G[_SCANNER .. "TextLeft" .. i]
			if (not line) then
				break
			end
			local bind = GetBindType(line:GetText())
			if (bind) then
				category = bind
				break
			end
		end
		Scanner:Hide()
	end

	return category
end

function filter:GetCategoryLabel(category, itemId)
	if not category then return nil end

	if (category == S_BOE) and self.db.profile.enableBoE then
		return L[S_BOE]
	elseif (category == S_BOA) and self.db.profile.enableBoA then
		return L[S_BOA]
	elseif (category == S_BOP) and self.db.profile.enableBoP then
		if (self.db.profile.onlyEquipableBoP) then
			if (self:IsItemEquipable(itemId)) then
				return L[S_BOP]
			end
		else
			return L[S_BOP]
		end
	end
end

function filter:IsItemEquipable(itemId)
	-- Inventory type 0 is INVTYPE_NON_EQUIP: Non-equipable
	return not (C_Item_GetItemInventoryTypeByID(itemId) == 0)
end

-- Setup the environment
-----------------------------------------------------------
(function(self)
	-- Private Default API
	-- This mostly contains methods we always want available
	-----------------------------------------------------------

	-- Addon version
	-- *Keyword substitution requires the packager,
	-- and does not affect direct GitHub repo pulls.
	local version = "@project-version@"
	if (version:find("project%-version")) then
		version = "DEV"
	end

	-- WoW Client versions
	local currentClientPatch, currentClientBuild = GetBuildInfo()
	currentClientBuild = tonumber(currentClientBuild)

	local MAJOR, MINOR, PATCH = string_split(".", currentClientPatch)
	MAJOR = tonumber(MAJOR)

	-- WoW Client versions
	local patch, build, date, version = GetBuildInfo()
	Private.IsRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
	Private.IsClassic = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)
	Private.IsTBC = (WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
	Private.IsWrath = (WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC)
	-- while the pre-patch is 100000, some APIs we need only arrive with 100002
	Private.WoW10 = version >= 100002

	-- Should mostly be used for debugging
	Private.Print = function(self, ...)
		print("|cff33ff99AdiBags_Bound:|r", ...)
	end

	Private.PrintTable = function(self, tbl, name, indent)
		if not indent then indent = "" end
		print(indent, name)

		-- https://gist.github.com/stuby/5445834#file-rprint-lua
		-- recursive Print (structure, limit, indent)
		local function rPrint(s, l, i)
			l = (l) or 100;
			if (l < 1) then print "ERROR: Item limit reached."; return l - 1 end
			local ts = type(s);
			if (ts ~= "table") then print(i, ts, s); return l - 1 end
			print(i, ts); -- print "table"
			for k, v in pairs(s) do -- print "[KEY] VALUE"
				l = rPrint(v, l, i .. "\t[" .. tostring(k) .. "]");
				if (l < 0) then break end
			end
			return l
		end

		rPrint(tbl, 1000, indent)
	end

	Private.GetAddOnInfo = function(self, index)
		local name, title, notes, loadable, reason, security, newVersion = GetAddOnInfo(index)
		local enabled = not (GetAddOnEnableState(UnitName("player"), index) == 0)
		return name, title, notes, enabled, loadable, reason, security
	end

	-- Check if an addon exists in the addon listing and loadable on demand
	Private.IsAddOnLoadable = function(self, target, ignoreLoD)
		local target = string.lower(target)
		for i = 1, GetNumAddOns() do
			local name, title, notes, enabled, loadable, reason, security = self:GetAddOnInfo(i)
			if string.lower(name) == target then
				if loadable or ignoreLoD then
					return true
				end
			end
		end
	end

	-- This method lets you check if an addon WILL be loaded regardless of whether or not it currently is.
	-- This is useful if you want to check if an addon interacting with yours is enabled.
	-- My philosophy is that it's best to avoid addon dependencies in the toc file,
	-- unless your addon is a plugin to another addon, that is.
	Private.IsAddOnEnabled = function(self, target)
		local target = string.lower(target)
		for i = 1, GetNumAddOns() do
			local name, title, notes, enabled, loadable, reason, security = self:GetAddOnInfo(i)
			if string.lower(name) == target then
				if enabled and loadable then
					return true
				end
			end
		end
	end

	-- Event API
	-----------------------------------------------------------
	-- Proxy event registering to the addon namespace.
	-- The 'self' within these should refer to our proxy frame,
	-- which has been passed to this environment method as the 'self'.
	Private.RegisterEvent = function(_, ...) self:RegisterEvent(...) end
	Private.RegisterUnitEvent = function(_, ...) self:RegisterUnitEvent(...) end
	Private.UnregisterEvent = function(_, ...) self:UnregisterEvent(...) end
	Private.UnregisterAllEvents = function(_, ...) self:UnregisterAllEvents(...) end
	Private.IsEventRegistered = function(_, ...) self:IsEventRegistered(...) end

	-- Event Dispatcher and Initialization Handler
	-----------------------------------------------------------
	-- Assign our event script handler,
	-- which runs our initialization methods,
	-- and dispatches event to the addon namespace.
	self:RegisterEvent("ADDON_LOADED")
	self:SetScript("OnEvent", function(self, event, ...)
		if (event == "ADDON_LOADED") then
			-- Nothing happens before this has fired for your addon.
			-- When it fires, we remove the event listener
			-- and call our initialization method.
			if ((...) == Addon) then
				-- Delete our initial registration of this event.
				-- Note that you are free to re-register it in any of the
				-- addon namespace methods.
				self:UnregisterEvent("ADDON_LOADED")
				-- Call the initialization method.
				if (Private.OnInit) then
					Private:OnInit()
				end
				-- If this was a load-on-demand addon,
				-- then we might be logged in already.
				-- If that is the case, directly run
				-- the enabling method.
				if (IsLoggedIn()) then
					if (Private.OnEnable) then
						Private:OnEnable()
					end
				else
					-- If this is a regular always-load addon,
					-- we're not yet logged in, and must listen for this.
					self:RegisterEvent("PLAYER_LOGIN")
				end
				-- Return. We do not wish to forward the loading event
				-- for our own addon to the namespace event handler.
				-- That is what the initialization method exists for.
				return
			end
		elseif (event == "PLAYER_LOGIN") then
			-- This event only ever fires once on a reload,
			-- and anything you wish done at this event,
			-- should be put in the namespace enable method.
			self:UnregisterEvent("PLAYER_LOGIN")
			-- Call the enabling method.
			if (Private.OnEnable) then
				Private:OnEnable()
			end
			-- Return. We do not wish to forward this
			-- to the namespace event handler.
			return
		end
		-- Forward other events than our two initialization events
		-- to the addon namespace's event handler.
		-- Note that you can always register more ADDON_LOADED
		-- if you wish to listen for other addons loading.
		if (Private.OnEvent) then
			Private:OnEvent(event, ...)
		end
	end)
end)((function() return CreateFrame("Frame", nil, WorldFrame) end)())
