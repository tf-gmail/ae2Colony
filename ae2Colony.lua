local scriptName = "AE2 Colony"
local scriptVersion = "0.4.1"
local apVersions = {
  ["0.7.51b"] = true, -- script can crash if colonists are missing tools/weapons/armour
  ["0.7.55b"] = true, -- best version to use at the moment July 15'25
  ["0.7.57b"] = true  -- best version to use at the moment July 15'25
}
local requiredAP = advancedperipherals and advancedperipherals.getAPVersion()
if not apVersions[requiredAP] then
  error("Incompatible Advanced Peripherals version: " .. tostring(requiredAP))
end

--[[-------------------------------------------------------------------------------------------------------------------
author: toastonrye
https://github.com/toastonrye/ae2Colony/blob/main/README.md

Setup
Please see the Github for more detailed information!

Warning
This script was designed and tested in ATM10 modpack v4.2 with Advanced Peripherals 0.7.51b
Older or newer versions of Advanced Peripherals may not work!

Errors
For errors please see the Github, maybe I can help..!

Credits
Chezlordgaming - Contributions to tools & armour tier logic!
Srendi - Advanced Peripherals dev, fast support for bug troubleshooting!
---------------------------------------------------------------------------------------------------------------------]]

-- [USER CONFIG] ------------------------------------------------------------------------------------------------------
local exportSide = "front"
local craftMaxStack = false         -- Autocraft exact or a stack. ie 3 logs vs 64 logs.
local scanInterval = 30             -- Probably shouldn't go much lower than 20s...
local doLog = false                 -- Leave false unless you have issues. Kinda spammy!
local doLogExtra = false            -- If true more info printed to log file.
local logFolder = "ae2Colony_logs"
local maxLogs = 10
local maxLogSize = 200*1024 -- 100 KB
local alarm = nil                   -- Used to update monitor for errors.

-- [BLACKLIST & WHITELIST LOOKUPS] --------------------------------------------------------------------------------------------------------
-- blacklistedTags: all items matching the given tags are skipped, they do not export.
local blacklistedTags = {
  ["c:foods"] = true, -- I've noticed not all foods use tags, like at all! :(
  --["c:tools"] = true,
}

-- whitelistItemName: specific item names can be whitelisted.
-- If c:foods is blacklisted, whitelist minecraft:beef so colonists can cook into steaks!
-- QUESTION: Maybe no food should be whitelisted, the resturant seems to over-request food to cook up, filling warehouse??
local whitelistItemName = {
  --["minecraft:cod"] = true,
  ["minecraft:beef"] = true,
  ["minecraft:carrot"] = true,
  ["minecraft:potato"] = true,
  ["minecolonies:apple_pie"] = true,
}

-- [TOOLS & ARMOUR LOOKUPS]----------------------------------------------------------------------------------------------------
-- QUESTION: It maybe better to just have colonists make tools and armour?
-- gearNameHandler() replaces '$' with gold/diamond etc.
local gearTypes = {
  chestplate = "$_chestplate",
  boots      = "$_boots",
  leggings   = "$_leggings",
  helmet     = "$_helmet",
  sword      = "$_sword",
  pickaxe    = "$_pickaxe",
  axe        = "$_axe",
  shovel     = "$_shovel",
  hoe        = "$_hoe",
  shield     = "minecraft:shield",
  bow        = "minecraft:bow",
}

local gearMaterials = {
  wood = "minecraft:wooden",      -- I think desc refers to wood not wooden?
  leather = "minecraft:leather",
  stone = "minecraft:stone",
  chain = "minecraft:chainmail",
  iron = "minecraft:iron",
  gold = "minecraft:golden",      -- I think desc refers to gold not golden?
  diamond = "minecraft:diamond",
}

-- [LOGGING] ----------------------------------------------------------------------------------------------------------
if not fs.exists(logFolder) then fs.makeDir(logFolder) end

local function getNextLogFile()
  local files = fs.list(logFolder)
  table.sort(files)

  local numbered = {}
  for _, f in ipairs(files) do
    local n = f:match("^log_(%d+)%.log$")
    if n then table.insert(numbered, tonumber(n)) end
  end

  table.sort(numbered)

  local nextIndex = (numbered[#numbered] or 0) + 1
  return string.format("%s/log_%03d.log", logFolder, nextIndex)
end

local function logLine(line)
  if not doLog then return end
  local files = fs.list(logFolder)
  table.sort(files)
  local path
  if #files > 0 then
    local latest = files[#files]
    path = logFolder .. "/" .. latest
    if fs.getSize(path) >= maxLogSize then
      path = getNextLogFile()
    end
  else
    path = getNextLogFile()
  end
  local timestamp = os.date("%H:%M:%S", os.epoch("local") / 1000)
  local f = fs.open(path, "a")
  if f then
    f.writeLine(string.format("[%s] %s", timestamp, line))
    f.close()
  end
end

local function cleanupOldLogs()
  local files = fs.list(logFolder)
  local logFiles = {}
  for _, f in ipairs(files) do
    if f:match("^log_%d+%.log$") then
      table.insert(logFiles, f)
    end
  end
  table.sort(logFiles)
  while #logFiles > maxLogs do
    fs.delete(logFolder .. "/" .. table.remove(logFiles, 1))
  end
end

-- [MONITOR] ----------------------------------------------------------------------------------------------------------
local monitorLines = {}
local currentPage, totalPages = 1, 1
local function setupMonitor()
  local monitor = peripheral.find("monitor")
  if not monitor then return nil end
  monitor.setTextScale(0.5)
  monitor.clear()
  monitor.setCursorPos(1, 1)
  return monitor
end

local function updateMonitorGrouped(monitor)
  if not monitor then return end

  local width, height = monitor.getSize()
  local maxLines = height - 2
  local flatLines = {}

  local colorsMap = {
    CRAFT = colors.green,
    SENT = colors.lime,
    ERROR = colors.red,
    MISSING = colors.orange,
    MANUAL = colors.cyan,
    INFO = colors.yellow,
  }

  local groups = {
    ["ERROR"] = {},
    ["MISSING"] = {},
    ["CRAFT"] = {},
    ["SENT"] = {},
    ["MANUAL"] = {},
    ["INFO"] = {},
  }

  for _, line in ipairs(monitorLines) do
    for label in pairs(groups) do
      if line:find("%[" .. label .. "%]") then
        table.insert(groups[label], line)
        break
      end
    end
  end

  for label, entries in pairs(groups) do
    if #entries > 0 then
      table.insert(flatLines, {text = "== " .. label .. " ==", color = colors.white})
      for _, entry in ipairs(entries) do
        table.insert(flatLines, {text = entry, color = colorsMap[label] or colors.white})
      end
    end
  end

  totalPages = math.ceil(#flatLines / maxLines)
  if currentPage > totalPages then currentPage = 1 end
  local startLine = (currentPage - 1) * maxLines + 1
  local endLine = math.min(startLine + maxLines - 1, #flatLines)

  for y = 3, height do
    monitor.setCursorPos(1, y)
    monitor.write(string.rep(" ", width))
  end

  local y = 3
  for i = startLine, endLine do
    monitor.setCursorPos(1, y)
    monitor.setTextColor(flatLines[i].color)
    monitor.write(flatLines[i].text:sub(1, width))
    y = y + 1
  end
end

local function logAndDisplay(msg)
  logLine(msg)
  table.insert(monitorLines, msg)
end

-- [AP PERIPHERAL SETUP] ----------------------------------------------------------------------------------------------
local function setupPeripherals()
  term.clear()
  term.setCursorPos(1, 1)

  local bridge = peripheral.find("me_bridge") or error("me_bridge missing")
  local colony = peripheral.find("colony_integrator") or error("colony_integrator missing")
  if colony and not colony.isInColony then error("colony_integrator not in a colony") end
  return bridge, colony, setupMonitor()
end

local function confirmConnection(bridge)
  if bridge.isOnline() then
    return true
  end
  return false
end

-- [UTILS] ------------------------------------------------------------------------------------------------------------
local exportBuffer = {}
local function queueExport(fingerprint, count, name, target)
  table.insert(exportBuffer, {
    name = name,
    fingerprint = fingerprint,
    count = count,
    target = target
  })
end

local function processExportBuffer(bridge)
  for _, item in ipairs(exportBuffer) do
    local ok, result = pcall(function()
      return bridge.exportItem({
        fingerprint = item.fingerprint,
        name = item.name,
        count = item.count,
        components = {}
      }, exportSide)
    end)
    if not ok or not result then
      logAndDisplay(string.format("[ERROR] x%d %s [%s] > %s", item.count, item.name, item.fingerprint, item.target))
    else
      logAndDisplay(string.format("[SENT] x%d %s [%s] > %s", item.count, item.name, item.fingerprint, item.target))
    end
  end
end

local function alarmInfo(result)
end

-- [HANDLERS] ---------------------------------------------------------------------------------------------------------
-- AP fingerprints are amazing. Use "/advancedperipehrals getHashItem" in-game
local function bridgeDataHandler(bridge)
  local indexFingerprint = {}
  local ok, result = pcall(function()
    return bridge.getItems()
  end)
  if ok then
    for i = 1, #result do
      if result[i].fingerprint then indexFingerprint[result[i].fingerprint] = result[i] end
    end
  else
    logAndDisplay(string.format("[ERROR] ME Bridge Issues"))
  end
  return indexFingerprint
end

local function updateHeader(monitor, bridge, tick)
  if not monitor then return end

  local width, _ = monitor.getSize()
  local headerText = string.format("%s v%s", scriptName, scriptVersion)
  local status = confirmConnection(bridge)
  local statusText = status and "AE2 ONLINE" or "AE2 OFFLINE"
  local statusX = width - #statusText + 1

  monitor.setCursorPos(1, 1)
  monitor.setTextColor(colors.orange)
  monitor.write(string.rep(" ", width))
  monitor.setCursorPos(1, 1)
  monitor.write(headerText)

  monitor.setCursorPos(#headerText+3, 1)
  monitor.setTextColor(colors.lightBlue)
  monitor.write(string.format("Page %d of %d (right-click)", currentPage, totalPages))

  monitor.setCursorPos(statusX, 1)
  monitor.setTextColor(status and colors.lime or colors.red)
  monitor.write(statusText)

  monitor.setCursorPos(1, 2)
  monitor.setTextColor(colors.gray)
  monitor.write(string.rep("-", width))

  local filled = math.floor((tick / scanInterval) * width)
  monitor.setCursorPos(1, 2)
  monitor.setTextColor(status and colors.green or colors.red)
  monitor.write(string.rep("#", filled))
end

local function handleMonitorTouch(monitor)
  while true do
    local event, side, x, y = os.pullEvent("monitor_touch")
    if side == peripheral.getName(monitor) then
      currentPage = currentPage + 1
      if currentPage > totalPages then currentPage = 1 end
      updateMonitorGrouped(monitor)
    end
  end
end

local function colonyRequestHandler(colony)
  local ok, result = pcall(function()
    return colony.getRequests()
  end)
  if ok then
    if not next(result) then
      logAndDisplay(string.format("No Colony Requests Detected"))
      return
    else
      return result
    end
  else
    -- Reported to Advanced Peripherals Github, should be fixed in newer versions.
    -- https://github.com/IntelligenceModding/AdvancedPeripherals/issues/748
    -- In v0.7.51b colony.getRequests() can fail because colonists are missing basic tools, some issue with enchantment data.
    -- Put a few basic wooden swords/hoes/shovel/pickaxe/axes in your warehouse.
    -- Also do leather armour as well, I've seen a failure from enchantment "feather falling".
    alarm = result
    local msg = string.format("[ERROR] Critical failure for colony_integrator getRequests().")
    print(msg)
    logLine(msg)
    os.sleep(1)
  end
end

-- [CHEZ GEAR TIER LOOKUP]
-- This function builds from the gearTypes and gearMaterials tables.
local function gearNameHandler(request)
  local requestName = request and request.items[1] and request.items[1].name
  if requestName == "minecraft:bow" or requestName == "minecraft:shield" then
    return requestName
  end
  local gear = string.lower(request.name or "")
  local desc = string.lower(request.desc or "")
  local maxLevel = string.match(desc, "maximal level:%s*(%w+)")
  if not maxLevel then return nil end
  local gearType = nil
  for key in pairs(gearTypes) do
    if gear:find(key) then
      gearType = gearTypes[key]
      break
    end
  end
  local gearMaterial = gearMaterials[maxLevel]
  if gearType and gearMaterial then
    local gearName = gearType:gsub("%$", gearMaterial)
    return gearName
  end
  return nil
end

-- See blacklisted tags and whitelisted items table at top of script.
-- Basically blacklist an entire tag like c:foods then whitelist food for colonists to cook, like raw beef. Or carrots/potatoes for hospitals.
local function tagHandler(requestItem)
  if requestItem and whitelistItemName[requestItem.name] then
    return true, true
  elseif requestItem.tags then
    for _, tag in pairs(requestItem.tags) do
      if type(tag) == "string" then
        for blocked in pairs(blacklistedTags) do
          if tag:find("c:foods") then
            return true, false
          end
        end
      end
    end
  end
  return false, nil
end

-- Domum Ornamentum adds the Architect's Cutter, the player has to manually craft these special blocks.
-- QUESTION: Apparently colonists can also make them?
local function domumHandler(request)
  local requestDisplayName = request.name
  local requestItem = request.items[1]
  local requestName = requestItem.name
  local requestFingerprint = requestItem.fingerprint
  local requestComponents = requestItem.components
  
  if requestName:find("domum_ornamentum") then
    local list, flip = {}, {}
    local textureData = requestComponents and requestComponents["domum_ornamentum:texture_data"]
    if textureData then
      for _, value in pairs(textureData) do
        table.insert(list, value)
      end
      for i = #list, 1, -1 do
        table.insert(flip, list[i])
      end
    end
    local blockState = requestComponents and requestComponents["minecraft:block_state"]
    if blockState then
      for _, value in pairs(blockState) do
        table.insert(flip, value)
      end
    end
    logAndDisplay(string.format("[MANUAL] %s - %s [%s]", requestDisplayName, requestName, requestFingerprint))
    for key, value in ipairs(flip) do
      logAndDisplay(string.format("[MANUAL] #%d %s", key, value))
    end
  end
end

-- QUESTION: handle prints to terminal, monitor, log, chatbox, rednet?
local function messageHandler()
  -- todo
end

-- Tries to craft by fingerprint first, if nil it tries by name. Fingerprint is the best match!
-- https://docs.advanced-peripherals.de/latest/guides/storage_system_functions/#objects
local function craftHandler(request, bridgeItem, bridge)
  local craftable = nil
  local payload = {}
  local ok, object = nil, nil
  -- isCraftable() currently can't use fingerprints as an item filter in AP 0.7.51b
  local fingerprintBridge = nil --bridgeItem and bridgeItem.fingerprint
  local fingerprintRequest = request.items[1].fingerprint
  local name = request.items[1].name
  local maxStackSize = request.items[1].maxStackSize
  local stackSize = (craftMaxStack and maxStackSize) or request.count

  if stackSize == 0 then stackSize = 1 end
  if fingerprintBridge then
    craftable = bridge.isCraftable({fingerprint = fingerprintBridge, count = stackSize})
    payload = {fingerprint = fingerprintBridge, count = stackSize}
  elseif name then
    craftable = bridge.isCraftable({name = name, components = {}, count = stackSize})
    payload = {name = name, count = stackSize, components = {}}
  end
  -- Sometimes craftable isn't true when I think it should be, so craftable items miss the first scan.
  -- QUESTION: I need to learn more about AE2 crafting object events, because this seems a bit buggy. Next scan usually works!
  if craftable then
    ok, object = pcall(function() return bridge.craftItem(payload) end)
    if ok then
      logAndDisplay(string.format("[CRAFT] x%d - %s [%s]", stackSize, name, fingerprintRequest))
    else
      logAndDisplay(string.format("[ERROR] Failed crafting: x%d - %s [%s]", stackSize, name, fingerprintBridge or fingerprintRequest or "Not Available"))
    end
  else
    logAndDisplay(string.format("[MISSING] No recipe x%d - %s [%s]", stackSize, name, fingerprintBridge or fingerprintRequest or "Not Available"))
  end
  return object
end

-- [MAIN HANDLER] -----------------------------------------------------------------------------------------------------
-- QUESTION: Watch for craft events maybe? https://docs.advanced-peripherals.de/latest/guides/storage_system_functions/#crafting-job
-- This is the main item exporting logic, eventually your colonists should be making foods, tools, domum ornamentum blocks, etc.
-- Case 1: First check for blacklisted tags like c:foods, then if specific food items are whitelisted before skipping export.
-- Case 2: Check for tool/armour requests, lookup material and export or craft is possible. Only non-enchanted gear.
-- Case 3. Export full requested item count, or craft if AE2 pattern exists. Export next scan cycle.
-- Case 4. No items available to export or crafting pattern to make. Make a pattern or do it manually. Or have your colonists do it.
local function mainHandler(bridge, colony)
  local colonyRequests = colonyRequestHandler(colony)
  local fallbackCache = {}
  local indexFingerprint = bridgeDataHandler(bridge)
  if not colonyRequests then
    logAndDisplay(string.format("[INFO] No colony requests detected!"))
    return
  end
  for _, request in ipairs(colonyRequests) do
    local requestCount = request.count or 0
    local requestItem = request.items[1]
    local requestTarget = request.target or request.name or "Unknown Target"

    local isTagBlacklisted, whitelistException = tagHandler(requestItem)
    local gearName = gearNameHandler(request)

    if requestItem then
      local requestFingerprint = requestItem.fingerprint
      local requestName = requestItem.name
      local bridgeItem = indexFingerprint[requestFingerprint]
      local debugInfo = requestName or requestFingerprint

      -- [CASE 1] Skip tag c:foods by default. Eventually your colonists should farm and cook meals!
      if isTagBlacklisted then
        if doLogExtra then logLine(string.format("[CASE 1] Tag Blacklisted [%s]", debugInfo)) end
        if whitelistException then
          local bridgeCount = (bridgeItem and bridgeItem.count) or 0
          --local countDelta = requestCount - bridgeCount
          if bridgeCount >= requestCount then
            if doLogExtra then logLine("[CASE 1] Whitelist Exception - Export Full") end
            queueExport(requestFingerprint, requestCount, requestName, requestTarget)
          else
            if doLogExtra then logLine("[CASE 1] Whitelist Exception - Craft") end
            local craftObject = craftHandler(request, bridgeItem, bridge)
          end
        else
          logAndDisplay(string.format("[INFO] Tag blacklist & item not whitelist. Skipping x%d %s", requestCount, requestItem.name))
        end
      -- [CASE 2] Matched keyword for tool or armour, try to export the max tiered material. Only non-enchanted.
      elseif gearName then
        if doLogExtra then logLine(string.format("[CASE 2] Gear Lookup [%s]", gearName)) end
        local gearStock = bridge.getItem({name = gearName, count = requestCount, components = {}})
        if gearStock and gearStock.count > 0 then
          if doLogExtra then logLine("[CASE 2] Gear In Stock: %s", gearName) end
          queueExport(nil, requestCount, gearName, requestTarget)
        else
          local simpleRequest = {
            count = requestCount,
            target = requestTarget,
            items = {
              {
                maxStackSize = requestItem.maxStackSize,
                name = gearName,
                components = {}
              }
            }
          }
          local craftObject = craftHandler(simpleRequest, nil, bridge)
        end
    -- [CASE 3] Export if items are available, or export partial and craft. Crafted items get exported next scan.
      elseif bridgeItem then
        if doLogExtra then logLine(string.format("[CASE 3] Bridge Item [%s]", debugInfo)) end
        local bridgeCount = bridgeItem.count or 0
        local countDelta = bridgeCount - requestCount
        if countDelta > 0 then
          if doLogExtra then logLine("[CASE 3] Bridge Item - Export Full") end
          queueExport(requestFingerprint, requestCount, requestName, requestTarget)
        elseif bridgeCount > 0 then
          if doLogExtra then logLine(string.format("[CASE 3] Bridge Item - Export & Craft [%s]", debugInfo)) end
          queueExport(requestFingerprint, bridgeCount, requestName, requestTarget)
          local craftObject = craftHandler(request, bridgeItem, bridge)
        else
          if doLogExtra then logLine("[CASE 3] Bridge Item - Craft") end
          local craftObject = craftHandler(request, bridgeItem, bridge)
        end
      -- [CASE 4] These items are not in stock, and/or don't have a recipe.
      --          Consider using colonists to craft things like Domum Ornamentum blocks.
      else
        if doLogExtra then logLine(string.format("[CASE 4] Bridge Item - No Craft, Only Manual[%s]", debugInfo)) end
        local domum = domumHandler(request)
        local craftObject = craftHandler(request, bridgeItem, bridge)
      end
    end
  end
end

-- [MAIN LOOP] --------------------------------------------------------------------------------------------------------
cleanupOldLogs()
local bridge, colony, monitor = setupPeripherals()
local title = string.format("[INFO] %s v%s initialized", scriptName, scriptVersion)
print(title)
logLine(title)

local function main()
  local tick = scanInterval
  while true do
    exportBuffer = {}
    monitorLines = {}
    mainHandler(bridge, colony)
    processExportBuffer(bridge)
    updateMonitorGrouped(monitor)

    while tick > 0 do
      local online = confirmConnection(bridge)
      if online then
        tick = tick - 1
      end
      updateHeader(monitor, bridge, tick)
      os.sleep(1)
    end
    tick = scanInterval
  end
end

parallel.waitForAll(
  main,
  function() handleMonitorTouch(monitor) end
)
