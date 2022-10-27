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


-- WoW API
-----------------------------------------------------------
local CreateFrame = _G.CreateFrame
local GetLocale = _G.GetLocale
local GetContainerItemInfo = _G.GetContainerItemInfo
local GetItemInfo = _G.GetItemInfo

-- WoW10 API
-----------------------------------------------------------
local C_Container_GetContainerItemInfo = C_Container and C_Container.GetContainerItemInfo

-- WoW Strings
-----------------------------------------------------------
local S_ITEM_BOP = ITEM_SOULBOUND
local S_ITEM_BOA = ITEM_ACCOUNTBOUND
local S_ITEM_BOA2 = ITEM_BNETACCOUNTBOUND
local S_ITEM_BOA3 = ITEM_BIND_TO_BNETACCOUNT
local S_ITEM_BOE = ITEM_BIND_ON_EQUIP

-- Constants
-----------------------------------------------------------
local S_BOA = "BoA"
local S_BOE = "BoE"

-- Localization system
-----------------------------------------------------------
-- Do not modify the function, 
-- just the locales in the table below!
local L = (function(tbl,defaultLocale) 
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
		for i,msg in pairs(tbl[defaultLocale]) do 
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
		["Bound"] = true,
		["Put BoE and BoA items in their own sections."] = true,
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

local filter = AdiBags:RegisterFilter("Bound", 92, "ABEvent-1.0")
filter.uiName = L["Bound"]
filter.uiDesc = L["Put BoE and BoA items in their own sections."]

function filter:OnInitialize()
	self.db = AdiBags.db:RegisterNamespace("Bound", {
		profile = {
			enableBoE = true,
			enableBoA = true,
		},
	})
end

function filter:Update()
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

--[[
	Item Qualities

	0 	Poor 		Poor
	1 	Common 		Common
	2 	Uncommon 	Uncommon
	3 	Rare 		Rare
	4 	Epic 		Epic
	5 	Legendary 	Legendary
	6 	Artifact 	Artifact
	7 	Heirloom 	Heirloom
	8 	WoWToken 	WoW Token
]]

--[[
	Bind Types

	0 	LE_ITEM_BIND_NONE
	1 	LE_ITEM_BIND_ON_ACQUIRE 	Bind on Pickup
	2 	LE_ITEM_BIND_ON_EQUIP 		Bind on Equip
	3 	LE_ITEM_BIND_ON_USE 		Bind on Use
	4 	LE_ITEM_BIND_QUEST
]]


-- Tooltip used for scanning.
-- Let's keep this name for all scanner addons.
local _SCANNER = "AVY_ScannerTooltip"
local Scanner = _G[_SCANNER] or CreateFrame("GameTooltip", _SCANNER, WorldFrame, "GameTooltipTemplate")

-- Cache of information objects,
-- globally available so addons can share it.
local Cache = AVY_ItemButtonInfoFrameCache or {}
AVY_ItemButtonInfoFrameCache = Cache

function filter:Filter(slotData)
	local itemLink, isBound, _
	local category = Cache[slotData.itemId] or nil

	if (category) then
		return L[category]
	end

	if (C_Container_GetContainerItemInfo) then
		local containerInfo = C_Container_GetContainerItemInfo(slotData.bag, slotData.slot)
		if (containerInfo) then
			itemLink = containerInfo.hyperlink
			isBound = containerInfo.isBound
		end
	else
		_, _, _, _, _, _, itemLink, _, _, _, isBound = GetContainerItemInfo(slotData.bag, slotData.slot)
	end

	if (itemLink) then
		local _, _, itemQuality, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemLink)

		-- Only parse items that are Uncommon and above, and are of type BoE or BoU
		if (itemQuality and itemQuality > 1) and (bindType == 2 or bindType == 3) then

			-- If the item is bound, the bind type is irrelevant.
			local ignoreItem = false
			if (isBound) then ignoreItem = true end

			-- GetContainerItemInfo isn't returning 'isBound' in the classics,
			-- so we need to scan the tooltip the old way here.
			if (isBound == nil) then
				Scanner.owner = self
				Scanner.bag = slotData.bag
				Scanner.slot = slotData.slot
				Scanner:SetOwner(self, "ANCHOR_NONE")
				Scanner:SetBagItem(slotData.bag, slotData.slot)
				for i = 2,6 do
					local line = _G[_SCANNER.."TextLeft"..i]
					if (not line) then
						break
					end
					local msg = line:GetText()
					if (msg) then
						if (string_find(msg, S_ITEM_BOP)) then
							-- item is bound, ignore
							ignoreItem = true
							Cache[slotData.itemId] = false
							break
						elseif (string_find(msg, S_ITEM_BOA) or string_find(msg, S_ITEM_BOA2) or string_find(msg, S_ITEM_BOA3)) then
							Cache[slotData.itemId] = S_BOA
							category = S_BOA
							break
						elseif (string_find(msg, S_ITEM_BOE)) then
							Cache[slotData.itemId] = S_BOE
							category = S_BOE
							break
						else
							ignoreItem = true
							Cache[slotData.itemId] = false
							break
						end
					end
				end
			end

			-- Only return if not ignored, nil means no filter
			if (!ignoreItem) then
				if (category == S_BOE) and filter.db.profile.enableBoE then
					return L[S_BOE]
				elseif (category == S_BOA) and filter.db.profile.enableBoA then
					return L[S_BOA]
				end
			end
		end
	end
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
	}, AdiBags:GetOptionHandler(self, false, function() return self:Update() end)
end
