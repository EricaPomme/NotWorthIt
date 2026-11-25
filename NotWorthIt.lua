------------------------------------------------------------------------------
-- NotWorthIt - flags items that are worth more to a vendor than on the
-- auction house, using Auctionator's price database.
--
-- Totally passive: no settings UI and no slash commands. Tune the
-- constants below and reload the UI.
--
-- Per item unit, the comparison is:
--
--   auction net = AH price * (1 - NWC_AUCTION_CUT) - deposit per unit
--   vendor bar  = vendor sell price * NWC_THRESHOLD
--
-- When a fresh auction price exists and the auction net lands below the
-- vendor bar, the item tooltip says so, and Baganator (if installed) can
-- flag the item as junk so it sorts with the trash.
------------------------------------------------------------------------------

local ADDON_NAME = "NotWorthIt"

--------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------

-- The auction house must beat the vendor price by this factor for an item
-- to be worth listing (1.02 = the auction needs to pay 2% more).
local NWC_THRESHOLD = 1.02

-- Ignore Auctionator prices older than this many days. Auctionator stores
-- prices in day buckets: 0 means "seen today", 1 means "today or yesterday",
-- and the default of 2 is a 48 hour threshold.
local NWC_FRESHNESS_DAYS = 2

-- Subtract the auction house listing deposit from the auction value. If an
-- auction fails to sell, the deposit is gone, and the net can end up below
-- what the vendor would have paid outright.
local NWC_INCLUDE_DEPOSIT = true

-- Deposit basis in hours: 2, 8 or 24 (Forever's auction durations, with
-- deposits of roughly 5% / 20% / 60% of the vendor price).
local NWC_AUCTION_DURATION = 8

-- The auction house keeps this share of a successful sale.
local NWC_AUCTION_CUT = 0.05

-- Bots briefly list a single unit at a crash price to bait matching tools
-- into underselling; the listing is bought back within seconds. When the
-- current price collapses far below the recent market recorded by
-- Auctionator, the outlier is ignored and the verdict uses the typical
-- price instead. Disable with false.
local NWC_SCAM_GUARD = true

-- Days of price history used to build the typical-price baseline.
local NWC_SCAM_DAYS = 7

-- A current price below this fraction of the baseline counts as bait.
local NWC_SCAM_RATIO = 0.5

-- Baganator runs one junk detector at a time, so while NotWorthIt is the
-- selected detector it also covers what would otherwise come from Dejunk.
-- Poor quality (grey) items with a vendor price are always junk: they
-- cannot be auctioned, so the vendor is their only buyer. Disable with
-- false.
local NWC_JUNK_POOR_QUALITY = true

-- Items that are still useful are never junk, even when the vendor pays
-- more than the auction house: consumables (food, potions, bandages) and
-- items kept in one of the player's equipment sets. These guards win over
-- everything except the grey rule above. Disable either with false.
local NWC_JUNK_IGNORE_CONSUMABLES = true
local NWC_JUNK_IGNORE_EQUIPMENT_SETS = true

-- A consumable only counts as useful while its required level is within
-- this many levels of the player's; older consumables are treated as
-- obsolete and left to Dejunk's rules and the vendor-versus-auction
-- verdict. Consumable tiers are spaced 10 levels apart, so 15 covers the
-- current tier plus one back - and at the level cap it keeps the final
-- tier (requirement 45 and up) protected instead of misclassifying it as
-- obsolete.
local NWC_JUNK_CONSUMABLE_LEVELS = 15

-- When Dejunk is installed, pass its junk answer through as well, so its
-- quality toggles, user lists and other rules keep working under Baganator
-- while NotWorthIt is the selected detector. Disable with false.
local NWC_JUNK_USE_DEJUNK = true

-- Print one chat line per hovered item explaining its verdict. Off by
-- default; flip to true while tuning or diagnosing.
local NWC_DEBUG = false

--------------------------------------------------------------------------
-- Derived constants
--------------------------------------------------------------------------

local DEPOSIT_RATES = { [2] = 0.05, [8] = 0.20, [24] = 0.60 }
-- Duration indexes understood by C_AuctionHouse: 1 short, 2 medium, 3 long.
local DURATION_INDEXES = { [2] = 1, [8] = 2, [24] = 3 }

local depositRate = DEPOSIT_RATES[NWC_AUCTION_DURATION]
local durationIndex = DURATION_INDEXES[NWC_AUCTION_DURATION]
if depositRate == nil or durationIndex == nil then
  print("|cffff2020NotWorthIt:|r NWC_AUCTION_DURATION must be 2, 8 or 24; using 8.")
  depositRate = DEPOSIT_RATES[8]
  durationIndex = DURATION_INDEXES[8]
end

-- Bind types that may still be listed on the auction house. Everything
-- else (soulbound, quest items, ...) has no auction value to compare.
local UNBOUND_BIND_TYPES = {}
if Enum and Enum.ItemBind then
  UNBOUND_BIND_TYPES[Enum.ItemBind.None] = true
  UNBOUND_BIND_TYPES[Enum.ItemBind.OnEquip] = true
  UNBOUND_BIND_TYPES[Enum.ItemBind.OnUse] = true
else
  UNBOUND_BIND_TYPES[LE_ITEM_BIND_NONE] = true
  UNBOUND_BIND_TYPES[LE_ITEM_BIND_ON_EQUIP] = true
  UNBOUND_BIND_TYPES[LE_ITEM_BIND_ON_USE] = true
end

-- Item quality and class used by the Baganator junk decision below.
local POOR_QUALITY = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0
local CONSUMABLE_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0

-- Green signature line shown when the auction house wins: the addon's own
-- name, with its "Not" struck out by a hand-positioned texture, so the
-- line reads "WorthIt". (Blizzard's text rendering has no native
-- strikethrough.)
local WORTH_IT_TEXT = "|cffff4c40Not|r|cff4cff40WorthIt|r"

--------------------------------------------------------------------------
-- Internal state (session only, nothing is saved to disk)
--------------------------------------------------------------------------

-- itemID -> per unit deposit measured against the live auction house.
-- Measured with one stack size; other stack sizes round slightly
-- differently, which is close enough for a warning.
local depositCache = {}

-- True while an auction house session is open; exact deposits are only
-- available during that window.
local ahOpen = false

-- Last debug line printed; repeats (hovering the same item, tooltip
-- refreshes) are suppressed so debugging does not spam the chat log.
local lastDebugMessage = nil

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

-- Money text with the game's coin icons, matching how Forever-native
-- addons render money, and handling negative net values.
local function MoneyString(value)
  value = math.ceil(value or 0)
  local sign = value < 0 and "-" or ""
  value = math.abs(value)

  local gold = math.floor(value / 10000)
  local silver = math.floor(value / 100) % 100
  local copper = value % 100
  local function coin(amount, kind)
    return amount .. "|TInterface\\MoneyFrame\\UI-" .. kind .. "Icon:12:12:1:0|t"
  end

  local text = gold > 0 and coin(gold, "Gold") .. " " or ""
  if silver > 0 or gold > 0 then text = text .. coin(silver, "Silver") .. " " end
  if copper > 0 or value == 0 then text = text .. coin(copper, "Copper") end
  return sign .. text:gsub("%s+$", "")
end

-- The piece of the Auctionator API we rely on, checked before every use so
-- the addon stays quiet when Auctionator is missing or out of date.
local function AuctionatorAPI()
  return Auctionator
    and Auctionator.API
    and Auctionator.API.v1
    and Auctionator.API.v1.GetAuctionPriceByItemID
    and Auctionator.API.v1.GetAuctionPriceByItemLink
    and Auctionator.API.v1.GetAuctionAgeByItemID
    and Auctionator.API.v1.GetAuctionAgeByItemLink
end

-- Typical market price for an item, built from Auctionator's day-bucketed
-- price history (read only): the highest minimum seen today, or failing
-- that the median of the previous days' minimums, whichever is higher. A
-- single bait listing can crash the stored minimum for seconds, but it can
-- only pull the day's LOWEST down - the highest minimum of the day and the
-- previous days' minimums keep recording the real market. Returns nil when
-- there is not enough history to judge.
local function GetPriceBaseline(itemID, itemLink)
  local store = Auctionator.Database and Auctionator.Database.db
  if type(store) ~= "table" then
    return nil
  end

  -- Resolve the same key family the price lookup used.
  local keys
  if itemLink ~= nil and Auctionator.Utilities
      and Auctionator.Utilities.DBKeyFromLink then
    Auctionator.Utilities.DBKeyFromLink(itemLink, function(resolved)
      keys = resolved
    end)
  end
  if keys == nil or #keys == 0 then
    keys = { tostring(itemID) }
  end

  local entry = nil
  for _, key in ipairs(keys) do
    entry = store[key]
    if entry ~= nil then
      break
    end
  end
  if type(entry) ~= "table" or type(entry.h) ~= "table"
      or Auctionator.Constants == nil
      or Auctionator.Constants.SCAN_DAY_0 == nil then
    return nil
  end

  local today = math.floor((time() - Auctionator.Constants.SCAN_DAY_0) / 86400)

  local previousLows = {}
  if type(entry.l) == "table" then
    for day = today - NWC_SCAM_DAYS + 1, today - 1 do
      local low = entry.l[tostring(day)]
      if type(low) == "number" and low > 0 then
        table.insert(previousLows, low)
      end
    end
    table.sort(previousLows)
  end

  local baseline = entry.h[tostring(today)]
  if type(baseline) ~= "number" or baseline <= 0 then
    baseline = nil
  end

  if #previousLows > 0 then
    -- Upper middle of the sorted lows: skews the baseline high, which is
    -- the conservative direction for calling something bait.
    local median = previousLows[math.ceil(#previousLows / 2)]
    if baseline == nil or median > baseline then
      baseline = median
    end
  end

  return baseline
end

-- Deposit cost for listing one item, preferring a real number from the
-- auction house. The exact APIs only answer while the AH is open and only
-- for items in our bags; otherwise fall back to the classic rates
-- (5% / 20% / 60% of the vendor value for 2 / 8 / 24 hour listings).
-- Note the estimate assumes a faction city auction house; neutral houses
-- charge more, and the exact path covers those automatically.
local function GetDepositPerUnit(itemID, itemLink, bagID, slotID)
  if not NWC_INCLUDE_DEPOSIT then
    return 0
  end

  local cached = depositCache[itemID]
  if cached ~= nil then
    return cached
  end

  if ahOpen and bagID ~= nil and slotID ~= nil
      and C_AuctionHouse ~= nil and ItemLocation ~= nil then
    local ok, perUnit = pcall(function()
      local location = ItemLocation.CreateFromBagAndSlot(bagID, slotID)
      if location == nil or not C_Item.DoesItemExist(location) then
        return nil
      end

      local info = C_Container.GetContainerItemInfo(bagID, slotID)
      local quantity = info and info.stackCount or 1
      if quantity < 1 then quantity = 1 end

      -- Mirror the value Blizzard's own post button passes to these APIs.
      local duration = durationIndex
      if type(AUCTION_DURATIONS) == "table" and AUCTION_DURATIONS[durationIndex] ~= nil then
        duration = AUCTION_DURATIONS[durationIndex]
      end

      local deposit
      if C_AuctionHouse.GetItemCommodityStatus(location) == Enum.ItemCommodityStatus.Commodity then
        deposit = C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, quantity)
      else
        deposit = C_AuctionHouse.CalculateItemDeposit(location, duration, quantity)
      end

      if type(deposit) ~= "number" or deposit < 0 then
        return nil
      end
      return math.ceil(deposit / quantity)
    end)

    if ok and perUnit ~= nil then
      depositCache[itemID] = perUnit
      return perUnit
    end
  end

  local itemInfo = { C_Item.GetItemInfo(itemLink or itemID) }
  local sellPrice = itemInfo[11]
  if sellPrice == nil then
    return 0
  end
  return math.ceil(sellPrice * depositRate)
end

-- Decide whether one item is worth more to a vendor than on the auction
-- house. Returns nil when nothing can be said (no data, stale price,
-- unsellable item), otherwise a table with the comparison numbers.
-- Link-based lookups are preferred so Auctionator's suffixed-item keys
-- (for example BoE greens) are honoured.
local function GetVerdict(itemID, itemLink, bagID, slotID, dbg)
  if itemID == nil and itemLink == nil then
    return nil
  end

  local itemInfo = { C_Item.GetItemInfo(itemLink or itemID) }
  if #itemInfo == 0 then
    if dbg then dbg("item data not cached yet") end
    return nil -- the next hover (or the tooltip refresh) will see it
  end

  local bindType = itemInfo[14]
  if bindType == nil or not UNBOUND_BIND_TYPES[bindType] then
    if dbg then dbg("cannot be auctioned (bind type " .. tostring(bindType) .. ")") end
    return nil
  end
  if C_Item.IsItemBindToAccountUntilEquip
      and C_Item.IsItemBindToAccountUntilEquip(itemInfo[2]) then
    if dbg then dbg("account bound until equipped") end
    return nil
  end

  local sellPrice = itemInfo[11]
  if sellPrice == nil or sellPrice <= 0 then
    if dbg then dbg("vendor pays nothing") end
    return nil
  end

  if not AuctionatorAPI() then
    if dbg then dbg("Auctionator API unavailable") end
    return nil
  end

  if itemID == nil then
    itemID = C_Item.GetItemInfoInstant(itemLink)
  end
  if itemID == nil then
    if dbg then dbg("no item ID in link") end
    return nil
  end

  -- When a link is available, only the link-based lookup is used: falling
  -- back to the base itemID could price a suffixed item (a specific BoE
  -- green) off a different suffix entirely.
  local price
  if itemLink ~= nil then
    price = Auctionator.API.v1.GetAuctionPriceByItemLink(ADDON_NAME, itemLink)
  else
    price = Auctionator.API.v1.GetAuctionPriceByItemID(ADDON_NAME, itemID)
  end
  if price == nil or price <= 0 then
    if dbg then dbg("no Auctionator price on record") end
    return nil
  end

  -- Undercut scam guard: when the current price collapses against the
  -- recent market, value the item at the typical price instead of the
  -- bait listing.
  local adjusted = false
  if NWC_SCAM_GUARD then
    local baseline = GetPriceBaseline(itemID, itemLink)
    if baseline ~= nil and price < baseline * NWC_SCAM_RATIO then
      if dbg then
        dbg(string.format(
          "undercut outlier ignored: %s is under %d%% of the %s baseline",
          MoneyString(price),
          math.floor(NWC_SCAM_RATIO * 100 + 0.5),
          MoneyString(baseline)))
      end
      price = baseline
      adjusted = true
    end
  end

  local age
  if itemLink ~= nil then
    age = Auctionator.API.v1.GetAuctionAgeByItemLink(ADDON_NAME, itemLink)
  else
    age = Auctionator.API.v1.GetAuctionAgeByItemID(ADDON_NAME, itemID)
  end

  -- A stale price is not a verdict. Report it (the tooltip shows an
  -- "outdated" note) but never flag the item as junk off old data.
  if age == nil or age > NWC_FRESHNESS_DAYS then
    if dbg then
      local ageText = age == nil and "unknown" or age .. " day(s)"
      dbg("price too old: age " .. ageText .. " exceeds the " ..
        NWC_FRESHNESS_DAYS .. " day limit")
    end
    return {
      stale = true,
      price = price,
      age = age,
    }
  end

  local depositPerUnit = GetDepositPerUnit(itemID, itemLink, bagID, slotID)
  local net = price * (1 - NWC_AUCTION_CUT) - depositPerUnit
  -- The hurdle the auction net must clear: the vendor price raised by the
  -- threshold factor. The flagged tooltip line reports the threshold as a
  -- percent instead of this number; the debug lines use it directly.
  local vendorBar = sellPrice * NWC_THRESHOLD

  return {
    notWorthIt = net < vendorBar,
    stale = false,
    adjusted = adjusted,
    vendor = sellPrice,
    vendorBar = vendorBar,
    net = net,
    price = price,
    deposit = depositPerUnit,
  }
end

--------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------

local hookedTooltips = {}
local function EnsureClearHook(tooltip)
  if hookedTooltips[tooltip] or not tooltip.ClearLines then
    return
  end
  hookedTooltips[tooltip] = true
  hooksecurefunc(tooltip, "ClearLines", function()
    tooltip.__NWCLine = nil
    tooltip.__NWCBag = nil
    if tooltip.__NWCStrike ~= nil then
      tooltip.__NWCStrike:Hide()
    end
  end)
end

-- Blizzard's bag frames (and bag addons that use the same API) tell the
-- tooltip which slot they are showing via SetBagItem. Forever's GameTooltip
-- has no GetBagItem to read that back, so remember it as it is set; the
-- ClearLines hook above keeps it from ever pairing with a later, different
-- tooltip. This is what lets exact deposits be measured while the auction
-- house is open.
local function HookGameTooltipBagItem()
  if GameTooltip == nil or GameTooltip.SetBagItem == nil then
    return
  end
  hooksecurefunc(GameTooltip, "SetBagItem", function(self, bagID, slotIndex)
    if bagID ~= nil and slotIndex ~= nil then
      self.__NWCBag = { bagID = bagID, slotID = slotIndex }
    else
      self.__NWCBag = nil
    end
  end)
  EnsureClearHook(GameTooltip)
end

-- Hidden font string used to measure text widths for the strike bar
-- without rendering anything.
local strikeMeasure
local function GetStrikeMeasure()
  if strikeMeasure == nil and GameTooltip ~= nil
      and GameTooltip.CreateFontString ~= nil then
    strikeMeasure = GameTooltip:CreateFontString()
    strikeMeasure:Hide()
  end
  return strikeMeasure
end

-- The red bar struck through the "Not" of the green signature line.
-- Blizzard's text rendering has no native strikethrough, so this is a
-- hand-positioned texture: left edge on the line's first glyph, width
-- measured from a hidden font string using the line's own font. The
-- ClearLines hook in EnsureClearHook hides it again on every rebuild.
local function AddStrikeBar(tooltip, lineFS)
  local measure = GetStrikeMeasure()
  if measure == nil then
    return
  end

  local fontPath, fontSize, fontFlags = lineFS:GetFont()
  if fontPath == nil then
    return
  end
  measure:SetFont(fontPath, fontSize, fontFlags)
  measure:SetText("Not")
  local width = measure:GetStringWidth()
  if width == nil or width <= 0 then
    return
  end

  local thickness = math.max(1, math.floor((fontSize or 12) / 12 + 0.5))

  local bar = tooltip.__NWCStrike
  if bar == nil then
    bar = tooltip:CreateTexture(nil, "OVERLAY")
    bar:SetColorTexture(1, 0.3, 0.25, 1)
    tooltip.__NWCStrike = bar
  end
  bar:ClearAllPoints()
  bar:SetPoint("LEFT", lineFS, "LEFT", 0, 0)
  bar:SetSize(width, thickness)
  bar:Show()
end

local function OnItemTooltip(tooltip)
  if tooltip.__NWCLine or tooltip:IsForbidden() then
    return
  end

  local name, link = tooltip:GetItem()
  if link == nil then
    return
  end

  local ok, itemID = pcall(C_Item.GetItemInfoInstant, link)
  if not ok or itemID == nil then
    return
  end

  local dbg
  if NWC_DEBUG then
    dbg = function(reason)
      if reason == lastDebugMessage then
        return -- unchanged; hovering the same item would otherwise spam
      end
      lastDebugMessage = reason
      print("|cffffd100NotWorthIt:|r " .. (name or tostring(itemID)) .. ": " .. reason)
    end
  end

  local bagID, slotIndex
  if tooltip.__NWCBag then
    bagID, slotIndex = tooltip.__NWCBag.bagID, tooltip.__NWCBag.slotID
  elseif tooltip.GetBagItem then
    bagID, slotIndex = tooltip:GetBagItem()
  end

  local verdict = GetVerdict(itemID, link, bagID, slotIndex, dbg)
  if verdict == nil then
    return -- the debug printer above already explained why
  end

  if verdict.stale then
    tooltip.__NWCLine = true
    EnsureClearHook(tooltip)
    if verdict.age ~= nil then
      tooltip:AddDoubleLine(
        "NotWorthIt: Auction data outdated",
        (verdict.age == 1 and "1 day old" or verdict.age .. " days old"),
        0.85, 0.65, 0.25,
        0.75, 0.75, 0.75
      )
    else
      tooltip:AddLine("NotWorthIt: Auction data outdated", 0.85, 0.65, 0.25)
    end
    return
  end

  if not verdict.notWorthIt then
    if dbg then
      dbg(string.format("AH wins: net %s >= vendor bar %s",
        MoneyString(verdict.net), MoneyString(verdict.vendorBar)))
    end

    -- Green signature line: the addon's own name with its "Not" struck
    -- out, so the line reads "WorthIt", with the margin over vendoring on
    -- the right.
    tooltip.__NWCLine = true
    EnsureClearHook(tooltip)
    tooltip:AddDoubleLine(
      WORTH_IT_TEXT,
      MoneyString(verdict.net - verdict.vendor) .. " more on AH"
        .. (verdict.adjusted and " (outlier ignored)" or ""),
      nil, nil, nil,
      1, 1, 1
    )

    -- The strike bar is cosmetic; skip it silently if anything is off.
    local tooltipName = tooltip:GetName()
    local lineFS = tooltipName
      and _G[tooltipName .. "TextLeft" .. tooltip:NumLines()]
    if lineFS ~= nil then
      AddStrikeBar(tooltip, lineFS)
    end
    return
  end

  if dbg then
    dbg(string.format("FLAGGED: net %s < vendor bar %s",
      MoneyString(verdict.net), MoneyString(verdict.vendorBar)))
  end

  tooltip.__NWCLine = true
  EnsureClearHook(tooltip)
  -- Both verdict lines share one shape: the addon's name on the left, the
  -- winning margin on the right. On this line the figure is the shortfall
  -- against the vendor bar (vendor price times NWC_THRESHOLD) - the margin
  -- the verdict acted on - which stays positive even when the raw vendor
  -- price sits below the auction net.
  tooltip:AddDoubleLine(
    "NotWorthIt",
    MoneyString(verdict.vendorBar - verdict.net) .. " more at vendor"
      .. (verdict.adjusted and " (outlier ignored)" or ""),
    1, 0.3, 0.25,
    1, 1, 1
  )
end

local function RegisterTooltipProcessing()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
      and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip then
        OnItemTooltip(tooltip)
      end
    end)
  end
end

--------------------------------------------------------------------------
-- Baganator
--------------------------------------------------------------------------

-- Best-effort equipment set membership, checked by item ID so the answer
-- survives the pieces moving between bags. Returns false when the
-- equipment set API is unavailable, so the guard quietly steps aside.
local function InEquipmentSet(itemID)
  if itemID == nil or C_EquipmentSet == nil
      or C_EquipmentSet.GetEquipmentSetIDs == nil
      or C_EquipmentSet.GetItemIDs == nil then
    return false
  end
  for _, setID in pairs(C_EquipmentSet.GetEquipmentSetIDs()) do
    local setItemIDs = C_EquipmentSet.GetItemIDs(setID)
    if type(setItemIDs) == "table" then
      for _, setItemID in pairs(setItemIDs) do
        if setItemID == itemID then
          return true
        end
      end
    end
  end
  return false
end

-- The Baganator junk decision. Baganator only runs one junk detector at a
-- time, so while NotWorthIt is selected it answers for the standard cases
-- too: greys are always junk, useful items are never junk, and Dejunk's own
-- rules keep applying through its public DejunkApi:IsJunk when it is
-- installed. Everything else falls back to the vendor-versus-auction
-- verdict. The tooltip verdict above is deliberately untouched: it answers
-- "what is the best way to sell this", not "is this trash".
local function GetBagJunk(bagID, slotID, itemID, itemLink)
  local itemInfo = { C_Item.GetItemInfo(itemLink or itemID) }

  -- Grey items with a vendor price: the vendor is their only buyer. This
  -- mirrors Baganator's own poor quality detector, which the selected
  -- plugin replaces.
  if NWC_JUNK_POOR_QUALITY and itemInfo[3] == POOR_QUALITY
      and (itemInfo[11] or 0) > 0 then
    return true
  end

  -- Useful-item guards, applying to everything except the grey rule above.
  if NWC_JUNK_IGNORE_CONSUMABLES and itemInfo[12] == CONSUMABLE_CLASS then
    -- Only useful consumables are protected: one that requires a level far
    -- below the player's is obsolete and left to Dejunk's rules and the
    -- verdict. Consumables with no required level cannot be dated this way
    -- and stay protected.
    local minLevel = itemInfo[5]
    local playerLevel = UnitLevel and UnitLevel("player") or 0
    if playerLevel == 0 or minLevel == nil or minLevel == 0
        or minLevel >= playerLevel - NWC_JUNK_CONSUMABLE_LEVELS then
      return false
    end
  end
  if NWC_JUNK_IGNORE_EQUIPMENT_SETS and InEquipmentSet(itemID) then
    return false
  end

  -- Dejunk's own answer, when it is installed: its quality toggles, user
  -- lists and other rules, exactly as configured in Dejunk.
  if NWC_JUNK_USE_DEJUNK and DejunkApi and type(DejunkApi.IsJunk) == "function" then
    local ok, isJunk = pcall(DejunkApi.IsJunk, DejunkApi, bagID, slotID)
    if ok and isJunk then
      return true
    end
  end

  local verdict = GetVerdict(itemID, itemLink, bagID, slotID)
  if verdict == nil or verdict.stale then
    return false -- unknown or outdated data is not junk
  end
  return verdict.notWorthIt
end

local baganatorRegistered = false
local function RegisterWithBaganator()
  if baganatorRegistered then
    return
  end
  if not (Baganator and Baganator.API and Baganator.API.RegisterJunkPlugin) then
    return
  end
  -- Without the Auctionator API the plugin could never flag anything, so
  -- do not offer a dead option in Baganator's junk plugin menu.
  if not AuctionatorAPI() then
    return
  end
  baganatorRegistered = true

  -- Items the vendor beats, plus the standard junk cases above, get
  -- Baganator's junk coin and sort with the trash. Note Baganator only
  -- runs one junk plugin at a time; this one is auto-selected only when
  -- the player has not picked another.
  Baganator.API.RegisterJunkPlugin(ADDON_NAME, "notworthit", function(bagID, slotID, itemID, itemLink)
    return GetBagJunk(bagID, slotID, itemID, itemLink)
  end)
end

-- When Dejunk's settings or lists change, its junk answers change with
-- them; ask Baganator to redraw its junk markers. This mirrors what
-- Baganator itself does for its native Dejunk integration.
local dejunkRefreshRegistered = false
local function RegisterDejunkRefresh()
  if dejunkRefreshRegistered then
    return
  end
  if not (NWC_JUNK_USE_DEJUNK and DejunkApi and DejunkApi.Events
      and DejunkApi.AddListener and Baganator and Baganator.API
      and Baganator.API.RequestItemButtonsRefresh) then
    return
  end
  dejunkRefreshRegistered = true
  DejunkApi:AddListener(function(event)
    if event ~= DejunkApi.Events.BagsUpdated then
      -- Bag updates already trigger a refresh on their own.
      Baganator.API.RequestItemButtonsRefresh()
    end
  end)
end

--------------------------------------------------------------------------
-- Events and startup
--------------------------------------------------------------------------

RegisterTooltipProcessing()
HookGameTooltipBagItem()
RegisterWithBaganator()
RegisterDejunkRefresh()

-- After Auctionator processes new scan results, ask Baganator to refresh
-- its junk markers so freshly scanned prices take effect right away.
if Auctionator and Auctionator.API and Auctionator.API.v1
    and Auctionator.API.v1.RegisterForDBUpdate then
  Auctionator.API.v1.RegisterForDBUpdate(ADDON_NAME, function()
    if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
      Baganator.API.RequestItemButtonsRefresh()
    end
  end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    -- Auctionator, Baganator and Dejunk are listed in OptionalDeps and
    -- normally load first, but register here too in case load order
    -- changes.
    if arg1 == ADDON_NAME then
      RegisterWithBaganator()
      RegisterDejunkRefresh()
    elseif arg1 == "Baganator" then
      RegisterWithBaganator()
    elseif arg1 == "Dejunk" then
      RegisterDejunkRefresh()
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
  end
end)
