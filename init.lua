--[[
    BandoGear - Gear Swapper - v1.0.0 - 2023-01-05 - by Cannonballdex
    Fixed duplicate slot handling (ears, wrists, rings)
    Stable, deterministic, single-pass equip
--]]

---@type Mq
local mq = require('mq')
local LIP = require('lib.LIP')
local ICONS = require('mq.Icons')
require 'ImGui'

local args = {'BandoGear.ini'}
local settings = {}
local openGUI = true
local SaveSet, DeleteSet = "", ""

local function output(msg)
    print('\a-t[BandoGear] '..msg)
end

-------------------------------------------------
-- Utility
-------------------------------------------------

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function pack_open(i)
    return mq.TLO.Me.Inventory(i).Open() == 1
end

local function get_pack_name(i)
    return 'pack' .. (i - 22)
end

-------------------------------------------------
-- Duplicate slot rules
-------------------------------------------------

local DUPLICATE_SLOTS = {
    [1]=true, [2]=true,        -- Ears
    [9]=true, [10]=true,      -- Wrists
    [15]=true,[16]=true,      -- Fingers
}

-- Enforced equip order (RIGHT → LEFT)
local EQUIP_ORDER = {
    0,
    2,1,            -- Ear
    3,4,5,6,7,8,
    10,9,           -- Wrist
    11,12,13,14,
    16,15,          -- Finger
    17,18,19,20,21,22
}

-------------------------------------------------
-- Bag snapshot (physical item tracking)
-------------------------------------------------

local function collect_bag_items()
    local items = {}
    for bag = 23, 34 do
        local inv = mq.TLO.Me.Inventory(bag)
        if inv.Container() and inv.Container() > 0 then
            for slot = 1, inv.Container() do
                local item = inv.Item(slot)
                if item() then
                    table.insert(items, {
                        bag = bag,
                        slot = slot,
                        id = item.ID(),
                    })
                end
            end
        end
    end
    return items
end

local function pickup_from_bags(itemID, bagItems)
    for idx, entry in ipairs(bagItems) do
        if entry.id == itemID then
            if not pack_open(entry.bag) then
                mq.cmdf('/nomodkey /itemnotify %s rightmouseup', entry.bag)
                while not pack_open(entry.bag) do mq.delay(50) end
            end
            mq.cmdf(
                '/shift /itemnotify in %s %s leftmouseup',
                get_pack_name(entry.bag),
                entry.slot
            )
            table.remove(bagItems, idx)
            return true
        end
    end
    return false
end

-------------------------------------------------
-- Load / Save logic
-------------------------------------------------

local function save_settings()
    LIP.save(Settings_Path, settings)
end

local function loadset(name, action)
    if action == 'save' then
        settings[name] = {}
        for i = 0, 22 do
            settings[name]['GearSlot'..i] = mq.TLO.InvSlot(i).Item.ID()
        end
        save_settings()
        output('\aySaved Set "'..name..'"')
        return
    end

    if action == 'delete' then
        settings[name] = nil
        save_settings()
        output('\ayDeleted Set "'..name..'"')
        return
    end

    if not settings[name] then
        output('\arSet "'..name..'" does not exist')
        return
    end

    local bagItems = collect_bag_items()

    for _, slot in ipairs(EQUIP_ORDER) do
        local wanted = settings[name]['GearSlot'..slot]
        if wanted then
            local current = mq.TLO.InvSlot(slot).Item.ID()

            if current == wanted then goto continue end

            local isDup = DUPLICATE_SLOTS[slot]

            if isDup then
                if pickup_from_bags(wanted, bagItems) then
                    mq.delay(150)
                    mq.cmdf('/shift /itemnotify %d leftmouseup', slot)
                    mq.delay(150)
                    mq.cmd('/autoinventory')
                else
                    output(string.format(
                        '\aw(\atItem \ap%s\aw) \arMissing \ayfor slot \aw%s',
                        tostring(slot), tostring(wanted)
                    ))
                end
            else
                if pickup_from_bags(wanted, bagItems) or mq.TLO.FindItem(wanted)() then
                    mq.delay(150)
                    mq.cmdf('/shift /itemnotify %d leftmouseup', slot)
                    mq.delay(150)
                    mq.cmd('/autoinventory')
                else
                    output(string.format(
                        '\aw(\atItem \ap%s\aw) \arMissing \ayfor slot \aw%s',
                        tostring(wanted), tostring(slot)
                    ))
                end
            end
        end
        ::continue::
    end

    output('\agLoaded Set "'..name..'"')
end

-------------------------------------------------
-- GUI
-------------------------------------------------

local function bandogear()
    openGUI = ImGui.Begin('BandoGear - Gear Swapper', openGUI)

    ImGui.Text('Add Set:')
    ImGui.SameLine()
    SaveSet,_ = ImGui.InputText('##SaveSet', SaveSet)
    ImGui.SameLine()
    if ImGui.Button(ICONS.FA_USER_PLUS) then
        mq.cmdf('/loadset %s save', SaveSet)
    end

    ImGui.Text('Remove Set:')
    ImGui.SameLine()
    DeleteSet,_ = ImGui.InputText('##DeleteSet', DeleteSet)
    ImGui.SameLine()
    if ImGui.Button(ICONS.FA_USER_TIMES) then
        mq.cmdf('/loadset %s delete', DeleteSet)
    end

    ImGui.Separator()
    ImGui.Text('Existing Sets')

    for name,_ in pairs(settings) do
        if ImGui.Button(name) then
            mq.cmdf('/loadset %s', name)
        end
    end

    ImGui.End()
end

-------------------------------------------------
-- Setup
-------------------------------------------------

local function load_settings()
    Conf_Dir = mq.configDir:gsub('\\','/')..'/'
    Settings_Path = Conf_Dir..args[1]

    if file_exists(Settings_Path) then
    settings = LIP.load(Settings_Path) or {}
    -- normalize saved gear slot IDs to numbers where possible
    for setName, setData in pairs(settings) do
        if type(setData) == 'table' then
            for k,v in pairs(setData) do
                local n = tonumber(v)
                if n then setData[k] = n end
            end
        end
    end
else
    settings = {}
    save_settings()
end
end

local function setup()
    mq.bind('/ls', loadset)
    mq.bind('/loadset', loadset)
    load_settings()
    mq.imgui.init('bandogear', bandogear)
    output('\ayBandoGear Loaded')
end

setup()

while openGUI do
    mq.delay(100)
end
