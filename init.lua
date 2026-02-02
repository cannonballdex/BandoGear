--[[
    BandoGear - Gear Swapper - v1.0.0 - 2023-01-05 - by Cannonballdex
    Fixed duplicate slot handling (ears, wrists, rings)
    Stable, deterministic, single-pass equip
--]]

---@type Mq
local mq = require('mq')
local LCP = require('lib.LCP')
local ICONS = require('mq.Icons')
require 'ImGui'

-- ImGui helper
local function HelpMarker(desc)
  if not desc then return end
  if ImGui.IsItemHovered() then
    ImGui.BeginTooltip()
    ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
    ImGui.Text(desc)
    ImGui.PopTextWrapPos()
    ImGui.EndTooltip()
  end
end

-- Use a per-character settings file to keep databases independent per character
local args = {'BandoGear.ini'}

-- sanitize a name for use in a filename (keep alphanumerics, dash, underscore)
local function sanitize_filename(s)
    if not s then return 'unknown' end
    local str = tostring(s)
    -- replace any character not alphanumeric, dash or underscore with underscore
    str = str:gsub('[^%w%-_]', '_')
    return str
end

-- try to get the current character name; fall back to 'unknown' if unavailable
local charName = 'unknown'
local ok_name, name_val = pcall(function() return mq.TLO.Me and mq.TLO.Me.Name() end)
if ok_name and name_val and tostring(name_val) ~= '' then
    charName = tostring(name_val)
end

-- set the per-character settings filename (e.g. BandoGear_CharName.ini)
args[1] = ('BandoGear_%s.ini'):format(sanitize_filename(charName))

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

-- Try to ensure a directory exists. Uses lfs if available, falls back to os.execute.
local function ensure_dir(path)
    if not path or path == '' then return end
    local p = tostring(path):gsub('[\\/]+$','')
    local ok, lfs = pcall(require, 'lfs')
    if ok and lfs and lfs.mkdir then
        pcall(lfs.mkdir, p)
        return
    end
    pcall(function()
        if package.config:sub(1,1) == '\\' then
            os.execute('mkdir "' .. p .. '" >nul 2>&1')
        else
            os.execute('mkdir -p "' .. p .. '" >/dev/null 2>&1')
        end
    end)
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
-- Prefer augmented items when multiple identical items exist
-------------------------------------------------

-- Helper to detect whether a given inventory item has augments.
local function item_is_augmented(inv, slot)
    if not inv then return false end
    local ok, res = pcall(function() return inv.Item(slot).AugmentCount() end)
    if ok and type(res) == 'number' and res > 0 then return true end
    local ok2, a1 = pcall(function() return inv.Item(slot).Augment1() end)
    if ok2 and a1 and tostring(a1) ~= '' then return true end
    local ok3, augs = pcall(function() return inv.Item(slot).Augments() end)
    if ok3 and type(augs) == 'table' and #augs > 0 then return true end
    return false
end

local function collect_bag_items()
    local items = {}
    for bag = 23, 34 do
        local inv = mq.TLO.Me.Inventory(bag)
        if inv.Container() and inv.Container() > 0 then
            for slot = 1, inv.Container() do
                local item = inv.Item(slot)
                if item() then
                    local augmented = false
                    local ok, aug = pcall(item_is_augmented, inv, slot)
                    if ok and aug then augmented = true end
                    table.insert(items, {
                        bag = bag,
                        slot = slot,
                        id = item.ID(),
                        augmented = augmented,
                    })
                end
            end
        end
    end
    return items
end

-- Try to place whatever is on the cursor back into the specified pack/slot.
local function place_cursor_item_back_into(bag, slot)
    if not bag or not slot then return false end
    -- ensure pack open
    if not pack_open(bag) then
        mq.cmdf('/nomodkey /itemnotify %s rightmouseup', bag)
        local tries = 0
        while not pack_open(bag) and tries < 20 do mq.delay(50); tries = tries + 1 end
    end
    -- attempt to drop into the original slot (safe no-shift drop)
    pcall(function()
        mq.cmdf('/nomodkey /itemnotify in %s %s leftmouseup', get_pack_name(bag), slot)
    end)
    mq.delay(60)
    -- verify cursor cleared
    local ok, cur = pcall(function() return mq.TLO.Cursor.Item.ID() end)
    if ok and not cur then return true end
    return false
end

-- Try to place cursor item into the first available empty slot across known pack bags.
local function place_cursor_item_into_first_free()
    for bag = 23, 34 do
        local inv = mq.TLO.Me.Inventory(bag)
        if inv.Container() and inv.Container() > 0 then
            for slot = 1, inv.Container() do
                local ok, it = pcall(function() return inv.Item(slot) end)
                if ok and (not it() or tostring(it()) == '') then
                    if place_cursor_item_back_into(bag, slot) then return true end
                end
            end
        end
    end
    return false
end

-- Detect if confirmation dialog is visible
local function confirmation_visible()
    local ok, vis = pcall(function() return mq.TLO.Window('ConfirmationDialogBox').Open() end)
    if ok and vis then return true end
    return false
end

-- Press the ConfirmationDialogBox "No" button (user-provided notify)
local function press_confirmation_no()
    pcall(function()
        mq.cmd('/notify ConfirmationDialogBox CD_No_Button leftmouseup')
    end)
    mq.delay(60)
end

-- pickup_and_equip: try matching bag entries (augmented-first) and attempt to pick + equip.
-- If equipping triggers a confirmation dialog, press No, return the item to inventory, and try the next match.
-- Returns true on successful equip (and removes that bag entry from bagItems), false otherwise.
local function pickup_and_equip_from_bags(itemID, bagItems, target_slot)
    if not itemID or not bagItems or target_slot == nil then return false end

    -- Build a list of indices: augmented-first, then others
    local augmented_indices = {}
    local normal_indices = {}
    for i,entry in ipairs(bagItems) do
        if entry.id == itemID then
            if entry.augmented then table.insert(augmented_indices, i)
            else table.insert(normal_indices, i) end
        end
    end

    local try_indices = {}
    for _,i in ipairs(augmented_indices) do table.insert(try_indices, i) end
    for _,i in ipairs(normal_indices) do table.insert(try_indices, i) end

    -- Try each candidate index
    for _, idx in ipairs(try_indices) do
        local entry = bagItems[idx]
        if not entry then goto continue_try end

        -- open pack if needed
        if not pack_open(entry.bag) then
            mq.cmdf('/nomodkey /itemnotify %s rightmouseup', entry.bag)
            local tries = 0
            while not pack_open(entry.bag) and tries < 20 do mq.delay(50); tries = tries + 1 end
        end

        -- pick up the item onto cursor
        pcall(function()
            mq.cmdf('/shift /itemnotify in %s %s leftmouseup', get_pack_name(entry.bag), entry.slot)
        end)
        mq.delay(120)

        -- attempt to equip into the target slot
        pcall(function()
            mq.cmdf('/shift /itemnotify %d leftmouseup', target_slot)
        end)
        mq.delay(150)

        -- If confirmation dialog visible, press No and put item back, then continue to next item
        if confirmation_visible() or (pcall(function() return mq.TLO.Cursor.Item.ID() end) and mq.TLO.Cursor.Item.ID()) then
            -- Press No
            press_confirmation_no()
            mq.delay(80)
            -- If still on cursor, try to return to same pack/slot
            local ok_cur, curid = pcall(function() return mq.TLO.Cursor.Item.ID() end)
            if ok_cur and curid then
                -- Try to return to original slot first
                local returned = place_cursor_item_back_into(entry.bag, entry.slot)
                if not returned then
                    -- fallback to first free slot elsewhere
                    place_cursor_item_into_first_free()
                end
            end
            -- item was returned (or attempt made), continue to next candidate
            goto continue_try
        end

        -- Check if equip succeeded (InvSlot now has the wanted ID)
        local ok_cur2, newid = pcall(function() return mq.TLO.InvSlot(target_slot).Item.ID() end)
        if ok_cur2 and newid == itemID then
            -- remove used entry from bagItems
            table.remove(bagItems, idx)
            return true
        end

        ::continue_try::
    end

    return false
end

-------------------------------------------------
-- Load / Save logic
-------------------------------------------------

local function save_settings()
    LCP.save(Settings_Path, settings)
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
                if pickup_and_equip_from_bags(wanted, bagItems, slot) then
                    mq.delay(150)
                    mq.cmd('/autoinventory')
                else
                    output(string.format(
                        '\aw(\atItem \ap%s\aw) \arMissing \ayfor slot \aw%s',
                        tostring(slot), tostring(wanted)
                    ))
                end
            else
                if pickup_and_equip_from_bags(wanted, bagItems, slot) or mq.TLO.FindItem(wanted)() then
                    -- If pickup_and_equip_from_bags succeeded, it's already equipped.
                    -- If not, but FindItem returned true, attempt a direct equip and handle confirmation fallback.
                    if not pickup_and_equip_from_bags(wanted, bagItems, slot) then
                        pcall(function()
                            mq.delay(150)
                            mq.cmdf('/shift /itemnotify %d leftmouseup', slot)
                        end)
                        mq.delay(150)
                        if confirmation_visible() or (pcall(function() return mq.TLO.Cursor.Item.ID() end) and mq.TLO.Cursor.Item.ID()) then
                            press_confirmation_no()
                            mq.delay(80)
                            -- return whatever is on cursor into first free slot
                            place_cursor_item_into_first_free()
                            -- continue to next matching item (we treated this attempt as failed)
                            goto continue
                        end
                        mq.delay(150)
                        mq.cmd('/autoinventory')
                    else
                        mq.delay(150)
                        mq.cmd('/autoinventory')
                    end
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
    -- Set a wider default size for the window (width, height).
    -- Adjust these numbers to taste (e.g. 700, 320).
    ImGui.SetNextWindowSize(300, 300)
    openGUI = ImGui.Begin('BandoGear - By Cannonballdex', openGUI)

    if ImGui.Button(string.format('%s Save Set', ICONS.FA_USER_PLUS)) then
        mq.cmdf('/BandoGear %s save', SaveSet)
    end
    HelpMarker('Enter a name (No Spaces) for the set to save, then click "Save Set".')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(150)
    SaveSet,_ = ImGui.InputText('##SaveSet', SaveSet)
    
    ImGui.Separator()
    ImGui.Text('Existing Sets')

    -- Build sorted list of set names for stable display
    local setNames = {}
    for name,_ in pairs(settings) do table.insert(setNames, name) end
    table.sort(setNames, function(a,b) return tostring(a):lower() < tostring(b):lower() end)

    -- Scrollable area for sets; using a child keeps the window tidy for many sets
    ImGui.BeginChild('SetsList', 0, -ImGui.GetFrameHeightWithSpacing(), true)

    if #setNames == 0 then
        ImGui.TextColored(1,0.8,0.2,1, 'No saved sets')
    else
        for _, name in ipairs(setNames) do
            ImGui.PushID(name)

            -- Main set button (loads the set)
            if ImGui.Button(name) then
                mq.cmdf('/BandoGear %s', name)
            end
            HelpMarker('Click the Equip this set.')
            -- Place delete button to the right of the set button
            ImGui.SameLine()
            if ImGui.Button(string.format('%s Delete Set', ICONS.FA_USER_TIMES)) then
                mq.cmdf('/BandoGear %s delete', name)
            end

            ImGui.PopID()
        end
        HelpMarker('Click the Delete button to remove the set.')
    end

    ImGui.EndChild()

    ImGui.End()
end

-------------------------------------------------
-- Setup
-------------------------------------------------

local function load_settings()
    Conf_Dir = mq.configDir:gsub('\\','/')..'/'
    -- store per-character settings in the config/BandoGear/ folder
    local store_dir = Conf_Dir .. 'BandoGear/'
    ensure_dir(store_dir)

    Settings_Path = store_dir .. args[1]

    if file_exists(Settings_Path) then
        settings = LCP.load(Settings_Path) or {}
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
    mq.bind('/BandoGear', loadset)
    load_settings()
    mq.imgui.init('bandogear', bandogear)
    output('\ayBandoGear Loaded')
end

setup()

while openGUI do
    mq.delay(100)
end
