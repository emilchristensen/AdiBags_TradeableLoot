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
local addon = LibStub("AceAddon-3.0"):GetAddon("AdiBags")

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

-- WoW Strings
-----------------------------------------------------------
local S_ITEM_BOP = ITEM_SOULBOUND
local S_ITEM_BOA = ITEM_ACCOUNTBOUND
local S_ITEM_BOA2 = ITEM_BNETACCOUNTBOUND
local S_ITEM_BOA3 = ITEM_BIND_TO_BNETACCOUNT
local S_ITEM_BOE = ITEM_BIND_ON_EQUIP

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
Private.L = L

--------------------------------------------------------------------------------
-- Filter Setup
--------------------------------------------------------------------------------

local filter = addon:RegisterFilter("Bound", 92, "ABEvent-1.0")
filter.uiName = L["Bound"]
filter.uiDesc = L["Put BoE and BoA items in their own sections."]

function filter:OnInitialize()
	self.db = addon.db:RegisterNamespace(self.filterName, {
		profile = {
			enableBoE = true,
			enableBoA = true,
		},
	})
end

function filter:GetOptions()
	return {
		enableBoE = {
			name = L["Enable BoE"],
			desc = L["Check this if you want a section for BoE items."],
			type = "toggle",
			order = 10,
		},
		enableBoA = {
			name = L["Enable BoA"],
			desc = L["Check this if you want a section for BoA items."],
			type = "toggle",
			order = 20,
		},
	}, addon:GetOptionHandler(self, false, function() return self:Update() end)
end

function filter:Update()
	self:SendMessage("AdiBags_FiltersChanged")
	addon:UpdateFilters()
end

function filter:OnEnable()
	addon:UpdateFilters()
end

function filter:OnDisable()
	addon:UpdateFilters()
end

--------------------------------------------------------------------------------
-- Actual filter - with a cache
--------------------------------------------------------------------------------

-- Tooltip used for scanning.
-- Let's keep this name for all scanner addons.
local _SCANNER = "AVY_ScannerTooltip"
local Scanner = _G[_SCANNER] or CreateFrame("GameTooltip", _SCANNER, WorldFrame, "GameTooltipTemplate")

-- Cache of information objects,
-- globally available so addons can share it.
local Cache = AVY_ItemBindInfoCache or {}
AVY_ItemBindInfoCache = Cache

function filter:Filter(slotData)
	if (Cache[slotData.itemId]) then
		return self:GetCategoryLabel(Cache[slotData.itemId])
	end

	local bag, slot, link, quality, itemId = slotData.bag, slotData.slot, slotData.link, slotData.quality, slotData.itemId

	if (link) then
		local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(link)
		local category = nil

		-- Only parse items that are Uncommon and above, and are of type BoP, BoE, and BoU
		if (quality and quality > 1) and (bindType > 0 and bindType < 4) then

			Scanner.owner = self
			Scanner.bag = bag
			Scanner.slot = slot
			Scanner:SetOwner(UIParent, "ANCHOR_NONE")
			Scanner:SetBagItem(bag, slot)
			for i = 2, 6 do
				local line = _G[_SCANNER .. "TextLeft" .. i]
				if (not line) then
					break
				end
				local msg = line:GetText()
				if (msg) then
					if (string_find(msg, S_ITEM_BOP)) then
						Cache[itemId] = S_BOP
						category = S_BOP
						break
					elseif (string_find(msg, S_ITEM_BOA) or string_find(msg, S_ITEM_BOA2) or string_find(msg, S_ITEM_BOA3)) then
						Cache[itemId] = S_BOA
						category = S_BOA
						break
					elseif (string_find(msg, S_ITEM_BOE)) then
						Cache[itemId] = S_BOE
						category = S_BOE
						break
					end
				end
			end

			return self:GetCategoryLabel(category)
		end
	end
end

function filter:GetCategoryLabel(category)
	if not category then return nil end

	if (category == S_BOE) and self.db.profile.enableBoE then
		return S_BOE
	elseif (category == S_BOA) and self.db.profile.enableBoA then
		return S_BOA
	else
		return nil
	end
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
		version = "Development"
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
	Private.WoW10 = version >= 100000

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
