if _G.__simplenavbar_loaded then return end
_G.__simplenavbar_loaded = true

local CFG = {
    icons_pack = "HeroIcons", -- from koreader/icons/tnb-icons/<folder>

    mode = "icons", -- "icons" | "text" | "both"
    buttons = {
        { id = "home",         enabled = true,  label = "Home"   },
        { id = "folder_up",    enabled = true,  label = "Up"     },
        { id = "continue",     enabled = true,  label = "Last"   },
        { id = "context_menu", enabled = true,  label = "Menu"   },
        { id = "settings",     enabled = true,  label = "Config" },
        { id = "restart",      enabled = true,  label = "Restart" },
    },

    lock_home = true,

    navbar_show_separator = true, -- top separator line above the navbar
    show_pagination       = false, -- show page info footer (restart required)

    titlebar             = true,
    titlebar_separator   = " • ",
    titlebar_show_border = false,
    titlebar_left        = "info",   -- "clock" = time only  |  "info" = time · model (at home) or time · folder name (elsewhere)
    titlebar_custom_model = "",      -- if set, replaces Device.model in "info" mode

    titlebar_show_wifi    = true,
    titlebar_show_frontlight = false,
    titlebar_show_ram     = true,
    titlebar_ram_pattern  = "$k%",
    titlebar_show_ssh     = true,
    titlebar_show_battery = true,
}

local FrameContainer  = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local IconWidget      = require("ui/widget/iconwidget")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local RightContainer  = require("ui/widget/container/rightcontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local UIManager       = require("ui/uimanager")
local InfoMessage     = require("ui/widget/infomessage")
local Geom            = require("ui/geometry")
local Font            = require("ui/font")
local Blitbuffer      = require("ffi/blitbuffer")
local Size            = require("ui/size")
local Device          = require("device")
local Screen          = Device.screen

-- Icons live in koreader/icons/tnb-icons/{pack}/{icon}.svg
-- We need the absolute path only for lfs scanning; IconWidget resolves relative to koreader/icons/
local DataStorage    = require("datastorage")
local TNB_ICONS_PATH = DataStorage:getDataDir() .. "/icons/tnb-icons"

local lfs = require("libs/libkoreader-lfs")
local ICON_PACKS = (function()
    local packs = {}
    if lfs.attributes(TNB_ICONS_PATH, "mode") ~= "directory" then return packs end
    for entry in lfs.dir(TNB_ICONS_PATH) do
        if entry ~= "." and entry ~= ".." then
            if lfs.attributes(TNB_ICONS_PATH .. "/" .. entry, "mode") == "directory" then
                packs[#packs + 1] = entry
            end
        end
    end
    table.sort(packs)
    return packs
end)()

local function _iconName(name)
    return "tnb-icons/" .. CFG.icons_pack .. "/" .. name
end

local ICON_MAP = {
    home         = "home",
    folder_up    = "up",
    continue     = "last",
    settings     = "settings",
    context_menu = "menu",
    restart      = "restart",
}

local _SETTINGS_KEY = "title_navbar"

local function _saveSettings()
    G_reader_settings:saveSetting(_SETTINGS_KEY, {
        icons_pack            = CFG.icons_pack,
        mode                  = CFG.mode,
        lock_home             = CFG.lock_home,
        navbar_show_separator = CFG.navbar_show_separator,
        show_pagination       = CFG.show_pagination,
        titlebar              = CFG.titlebar,
        titlebar_left         = CFG.titlebar_left,
        titlebar_custom_model = CFG.titlebar_custom_model,
        titlebar_show_border  = CFG.titlebar_show_border,
        titlebar_show_wifi        = CFG.titlebar_show_wifi,
        titlebar_show_frontlight  = CFG.titlebar_show_frontlight,
        titlebar_show_ram     = CFG.titlebar_show_ram,
        titlebar_ram_pattern  = CFG.titlebar_ram_pattern,
        titlebar_show_ssh     = CFG.titlebar_show_ssh,
        titlebar_show_battery = CFG.titlebar_show_battery,
    })
end

local function _loadSettings()
    local s = G_reader_settings:readSetting(_SETTINGS_KEY)
    if not s then return end
    for k, v in pairs(s) do
        if CFG[k] ~= nil then CFG[k] = v end
    end
end

_loadSettings()

local TABS = (function()
    local t = {}
    for _, b in ipairs(CFG.buttons) do
        if b.enabled then
            local icon_key = b.id
            t[#t + 1] = {
                id    = b.id,
                label = b.label,
                icon  = _iconName(ICON_MAP[icon_key] or b.id),
            }
        end
    end
    return t
end)()
local NUM_TABS = #TABS

local _dim = {}
local function _invalidateDimCache() _dim = {} end

local function ICON_SZ()   if not _dim.isz then _dim.isz = Screen:scaleBySize(44) end; return _dim.isz end
local function TOP_SP()    if not _dim.tsp then _dim.tsp = Screen:scaleBySize(2)  end; return _dim.tsp end
local function BOT_SP()    if not _dim.bsp then _dim.bsp = Screen:scaleBySize(12) end; return _dim.bsp end
local function SIDE_M()    if not _dim.sm  then _dim.sm  = Screen:scaleBySize(24) end; return _dim.sm  end
local function ICON_TSP()  if not _dim.its then _dim.its = Screen:scaleBySize(10) end; return _dim.its end
local function ICON_TXSP() if not _dim.itx then _dim.itx = Screen:scaleBySize(4)  end; return _dim.itx end
local function LABEL_FS()  if not _dim.lfs then _dim.lfs = Screen:scaleBySize(9)  end; return _dim.lfs end
local function SEP_H()     if not _dim.sh  then _dim.sh  = Screen:scaleBySize(1)  end; return _dim.sh  end
local function BAR_PAD()   if not _dim.bp  then _dim.bp  = Screen:scaleBySize(14) end; return _dim.bp  end
local function SCR_W()     if not _dim.sw  then _dim.sw  = Screen:getWidth()      end; return _dim.sw  end
local function SCR_H()     if not _dim.sh2 then _dim.sh2 = Screen:getHeight()     end; return _dim.sh2 end

local function BAR_H()
    if not _dim.bh then
        local h = SEP_H() + ICON_TSP()
        if CFG.mode == "icons" or CFG.mode == "both" then h = h + ICON_SZ() end
        if CFG.mode == "both" then h = h + ICON_TXSP() end
        if CFG.mode == "text" or CFG.mode == "both" then h = h + LABEL_FS() + Screen:scaleBySize(4) end
        _dim.bh = h + BAR_PAD()
    end
    return _dim.bh
end

local function TOTAL_H()
    if not _dim.th then _dim.th = BAR_H() + TOP_SP() + BOT_SP() end
    return _dim.th
end

local function _contentH()
    if not _dim.ch then _dim.ch = SCR_H() - TOTAL_H() end
    return _dim.ch
end

local C_SEP      = Blitbuffer.gray(0.7)

local active_id          = "home"
local fm_context_menu_cb = nil
local fm_ref             = nil

local function normalizePath(p)
    return (p or "/"):gsub("/$", "")
end

local _tb_bar_font = Font:getFace("xx_smallinfofont")
local _tb_h_pad    = Screen:scaleBySize(10)

local function _tbGetWifi()
    if not CFG.titlebar_show_wifi then return nil end
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok then return nil end
    return NetworkMgr:isWifiOn() and "" or ""
end

local function _tbGetFrontlight()
    if not CFG.titlebar_show_frontlight then return nil end
    local ok, result = pcall(function()
        local powerd = Device:getPowerDevice()
        if not powerd then return nil end
        local fl_on = powerd:isFrontlightOn()
        if not fl_on then return nil end
        local intensity = powerd:frontlightIntensity()
        if not intensity or intensity == 0 then return nil end
        local s = "☼ " .. intensity .. "%"
        local ok_w, warmth = pcall(function() return powerd:frontlightWarmth() end)
        if ok_w and warmth and warmth > 0 then
            s = s .. "💡 " .. warmth .. "%"
        end
        return s
    end)
    if not ok then return nil end
    return result
end

local function _tbGetRam()
    if not CFG.titlebar_show_ram then return nil end
    local statm = io.open("/proc/self/statm", "r")
    if not statm then return nil end
    local _, rss = statm:read("*number", "*number")
    statm:close()
    if not rss then return nil end
    local ko_kb = rss * 4

    local mem_total, mem_available
    local f = io.open("/proc/meminfo", "r")
    if f then
        for line in f:lines() do
            if line:find("MemTotal:")     then mem_total     = tonumber(line:match("%d+")) end
            if line:find("MemAvailable:") then mem_available = tonumber(line:match("%d+")) end
            if mem_total and mem_available then break end
        end
        f:close()
    end
    if not mem_total or mem_total == 0 then return nil end

    local ko_mb       = math.floor(ko_kb / 1024)
    local ko_gb       = string.format("%.2f", ko_kb / 1024 / 1024)
    local ko_pct      = math.floor((ko_kb / mem_total) * 100)
    local ko_pct_n    = ko_pct < 1 and "<1" or tostring(ko_pct)
    local sys_used_kb = mem_total - (mem_available or 0)
    local sys_mb      = math.floor(sys_used_kb / 1024)
    local sys_gb      = string.format("%.2f", sys_used_kb / 1024 / 1024)
    local sys_pct     = math.floor((sys_used_kb / mem_total) * 100)
    local sys_pct_n   = sys_pct < 1 and "<1" or tostring(sys_pct)
    local total_mb    = math.floor(mem_total / 1024)
    local total_gb    = string.format("%.2f", mem_total / 1024 / 1024)

    local pat = CFG.titlebar_ram_pattern or "$k%"
    local result = pat
        :gsub("%$Kg", ko_gb)
        :gsub("%$Ug", sys_gb)
        :gsub("%$Ag", total_gb)
        :gsub("%$k",  ko_pct_n)
        :gsub("%$K",  tostring(ko_mb))
        :gsub("%$u",  sys_pct_n)
        :gsub("%$U",  tostring(sys_mb))
        :gsub("%$A",  tostring(total_mb))
    return result ~= "" and ("" .. result) or nil
end

local function _tbGetSsh()
    if not CFG.titlebar_show_ssh then return nil end
    local ok, PluginLoader = pcall(require, "pluginloader")
    if not ok or not PluginLoader then return nil end
    local ssh = PluginLoader:getPluginInstance("SSH")
    if not ssh or not ssh:isRunning() then return nil end
    return ""
end

local function _tbGetBattery()
    if not CFG.titlebar_show_battery then return nil end
    if not Device:hasBattery() then return nil end
    local powerd = Device:getPowerDevice()
    local lvl = powerd:getCapacity()
    local sym = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), lvl)
    return sym .. lvl .. "%"
end

local function _tbBuildStatusRow()
    local sw  = SCR_W()
    local sep = CFG.titlebar_separator

    local left_text = os.date("%H:%M")
    if CFG.titlebar_left == "info" then
        local at_home = active_id == "home"
        local extra
        if at_home then
            extra = (CFG.titlebar_custom_model ~= "" and CFG.titlebar_custom_model) or Device.model or "KOReader"
        else
            local path = fm_ref and fm_ref.file_chooser and fm_ref.file_chooser.path
            extra = path and (path:match("([^/]+)/?$") or path) or nil
        end
        if extra then left_text = left_text .. sep .. extra end
    end
    local left = TextWidget:new{ text = left_text, face = _tb_bar_font }

    local rg    = HorizontalGroup:new{}
    local first = true
    for _, fn in ipairs({ _tbGetWifi, _tbGetFrontlight, _tbGetRam, _tbGetSsh, _tbGetBattery }) do
        local text = fn()
        if text then
            if not first and sep ~= "" then
                rg[#rg + 1] = TextWidget:new{ text = sep, face = _tb_bar_font }
            end
            rg[#rg + 1] = TextWidget:new{ text = text, face = _tb_bar_font }
            first = false
        end
    end

    local row_h = math.max(left:getSize().h, rg:getSize().h)

    local row = OverlapGroup:new{
        dimen = Geom:new{ w = sw, h = row_h },
        LeftContainer:new{
            dimen = Geom:new{ w = sw, h = row_h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = _tb_h_pad }, left },
        },
        RightContainer:new{
            dimen = Geom:new{ w = sw, h = row_h },
            HorizontalGroup:new{ rg, HorizontalSpan:new{ width = _tb_h_pad } },
        },
    }

    if not CFG.titlebar_show_border then return row end

    return VerticalGroup:new{
        align = "center",
        row,
        CenterContainer:new{
            dimen = Geom:new{ w = sw, h = Size.line.medium },
            LineWidget:new{
                dimen = Geom:new{ w = sw - _tb_h_pad * 2, h = Size.line.medium },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            },
        },
    }
end

local function _nbUpdateStatusBar(fm)
    local tb = fm and fm.title_bar
    if not tb or not tb.title_group then return end
    local tg = tb.title_group
    if #tg < 2 then return end
    tg[2] = _tbBuildStatusRow()
    tg:resetLayout()
    if #tg >= 3 then
        local used_h = 0
        for i = 1, 2 do used_h = used_h + tg[i]:getSize().h end
        local sub_h  = (#tg >= 4) and tg[4]:getSize().h or 0
        local area_h = tb.titlebar_height - used_h
        local new_pad = math.max(0, math.floor((area_h - sub_h) / 2))
        tg[3] = VerticalSpan:new{ width = new_pad }
        tg:resetLayout()
    end
    UIManager:setDirty(tb, "ui")
end

local function buildTabCell(tab, active, tab_w)
    local vg = VerticalGroup:new{ align = "center" }
    if CFG.navbar_show_separator then
        vg[#vg + 1] = LineWidget:new{ dimen = Geom:new{ w = tab_w, h = SEP_H() }, background = C_SEP }
    end
    vg[#vg + 1] = VerticalSpan:new{ width = ICON_TSP() }
    if CFG.mode == "icons" or CFG.mode == "both" then
        vg[#vg + 1] = IconWidget:new{ icon = tab.icon, width = ICON_SZ(), height = ICON_SZ(), fgcolor = Blitbuffer.COLOR_BLACK }
    end
    if CFG.mode == "text" or CFG.mode == "both" then
        if CFG.mode == "both" then vg[#vg + 1] = VerticalSpan:new{ width = ICON_TXSP() } end
        vg[#vg + 1] = TextWidget:new{ text = tab.label, face = Font:getFace("cfont", LABEL_FS()), fgcolor = Blitbuffer.COLOR_BLACK }
    end
    return CenterContainer:new{ dimen = Geom:new{ w = tab_w, h = BAR_H() }, vg }
end

local function buildBar(aid)
    local sw = SCR_W(); local sm = SIDE_M()
    local uw = sw - sm * 2; local bw = math.floor(uw / NUM_TABS)
    local hg = { align = "top" }
    for i = 1, NUM_TABS do
        hg[#hg + 1] = buildTabCell(TABS[i], TABS[i].id == aid, (i == NUM_TABS) and (uw - bw*(NUM_TABS-1)) or bw)
    end
    return FrameContainer:new{ bordersize = 0, padding = 0, padding_left = sm, padding_right = sm,
                               margin = 0, background = Blitbuffer.COLOR_WHITE, HorizontalGroup:new(hg) }
end

local function replaceBar(w, bar)
    if w._navbar_container then w._navbar_container[3] = bar; w._navbar_bar = bar end
end

local function wrapWithNavbar(inner, aid)
    local sw = SCR_W(); local bar = buildBar(aid)
    local c = VerticalGroup:new{ align = "left", inner,
        LineWidget:new{ dimen = Geom:new{ w = sw, h = TOP_SP() }, background = Blitbuffer.COLOR_WHITE },
        bar,
        LineWidget:new{ dimen = Geom:new{ w = sw, h = BOT_SP() }, background = Blitbuffer.COLOR_WHITE },
    }
    return c, FrameContainer:new{ bordersize = 0, padding = 0, margin = 0,
                                  background = Blitbuffer.COLOR_WHITE, c }, bar
end

local function registerTouchZones(target, exec_fn)
    local sw = SCR_W(); local sh = SCR_H()
    local sm = SIDE_M(); local uw = sw - sm * 2
    local tw = math.floor(uw / NUM_TABS); local by = sh - BAR_H() - BOT_SP()
    if target.unregisterTouchZones then
        local old = {}
        for i = 1, NUM_TABS do old[#old + 1] = { id = "navbar_pos_" .. i } end
        target:unregisterTouchZones(old)
    end
    local zones = {}
    for i = 1, NUM_TABS do
        local tab    = TABS[i]
        local x0     = sm + (i-1)*tw
        local this_w = (i == NUM_TABS) and (uw - tw*(NUM_TABS-1)) or tw
        zones[#zones + 1] = { id = "navbar_pos_"..i, ges = "tap",
            screen_zone = { ratio_x = x0/sw, ratio_y = by/sh, ratio_w = this_w/sw, ratio_h = BAR_H()/sh },
            handler = function(_ges) exec_fn(tab, target); return true end }
    end
    target:registerTouchZones(zones)
end

local function rebuildAll()
    local seen = {}
    local function rebuild(w)
        if not w or not w._navbar_container or seen[w] then return end
        seen[w] = true
        replaceBar(w, buildBar(active_id))
        if w._navbar_exec_fn then registerTouchZones(w, w._navbar_exec_fn) end
        UIManager:setDirty(w._navbar_container, "ui")
    end
    if fm_ref then rebuild(fm_ref) end
    for _, e in ipairs(UIManager._window_stack) do rebuild(e.widget) end
end

local function showMsg(msg)
    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
end

local function execute(tab, target)
    active_id = tab.id
    if target._navbar_container then
        replaceBar(target, buildBar(tab.id)); UIManager:setDirty(target._navbar_container, "ui")
    end
    local fm = fm_ref
    if fm and target ~= fm then
        if not (tab.id == "continue" and (target.name or "") == "history") then
            if target.onCloseAllMenus then target:onCloseAllMenus()
            elseif target.onClose     then target:onClose() end
        end
        if fm._navbar_container then replaceBar(fm, buildBar(tab.id)); UIManager:setDirty(fm._navbar_container, "ui") end
    end
    if not fm then return end

    if tab.id == "home" then
        local home = G_reader_settings:readSetting("home_dir")
        if home and fm.file_chooser then fm.file_chooser:changeToPath(home)
        elseif fm.onHome then fm:onHome() end

    elseif tab.id == "folder_up" then
        if fm.file_chooser then
            local home   = G_reader_settings:readSetting("home_dir")
            local cur    = normalizePath(fm.file_chooser.path)
            local parent = cur:match("^(.+)/[^/]+$") or "/"

            if CFG.lock_home and home then
                home = normalizePath(home)
                if cur == home then
                    showMsg("Already at home folder.")
                    return
                end
                if #parent < #home then
                    fm.file_chooser:changeToPath(home)
                    return
                end
            end

            fm.file_chooser:changeToPath(parent)
        end

    elseif tab.id == "continue" then
        local ok, RH = pcall(require, "readhistory")
        if ok then RH:reload(); local l = RH.hist and RH.hist[1]
            if l and l.file then active_id = "home"
                require("apps/reader/readerui"):showReader(l.file); return end end
        showMsg("No books in history.")

    elseif tab.id == "settings" then
        UIManager:scheduleIn(0.1, function()
            if not pcall(function() fm:onTapHamburgerMenu() end) then
                if not pcall(function() fm:handleEvent(require("ui/event"):new("ShowMenu")) end) then
                    showMsg("Settings not available.") end end
        end)

    elseif tab.id == "context_menu" then
        UIManager:scheduleIn(0.1, function()
            if fm_context_menu_cb then pcall(fm_context_menu_cb)
            elseif not pcall(function() fm:onShowFolderMenu() end) then
                showMsg("Context menu not available.") end
        end)

    elseif tab.id == "restart" then
        G_reader_settings:flush()
        local ok, EC = pcall(require, "exitcode")
        UIManager:quit((ok and EC and EC.restart) or 85)
    end
end

local FileChooser = require("ui/widget/filechooser")

local orig_genItems = FileChooser.genItemTableFromPath
if orig_genItems then
    FileChooser.genItemTableFromPath = function(fc_self, path)
        local items = orig_genItems(fc_self, path)
        if type(items) == "table" then
            for i = #items, 1, -1 do
                local it = items[i]
                if it and (it.text == ".." or (type(it.path) == "string" and it.path:sub(-3) == "/..")) then
                    table.remove(items, i)
                end
            end
        end
        return items
    end
end

local function installRecalcOverride(fc)
    if fc._nb_recalc_installed then return end
    fc._nb_recalc_installed = true
    fc._recalculateDimen = function(self_inner, no_recalc)
        if CFG.show_pagination then
            self_inner._recalculateDimen = nil
            self_inner:_recalculateDimen(no_recalc)
            self_inner._recalculateDimen = fc._recalculateDimen
            return
        end
        local sv_arrow = self_inner.page_return_arrow
        local sv_text  = self_inner.page_info_text
        local sv_info  = self_inner.page_info
        self_inner.page_return_arrow = nil
        self_inner.page_info_text    = nil
        self_inner.page_info         = nil
        local instance_fn = self_inner._recalculateDimen
        self_inner._recalculateDimen = nil
        self_inner:_recalculateDimen(no_recalc)
        self_inner._recalculateDimen = instance_fn
        self_inner.page_return_arrow = sv_arrow
        self_inner.page_info_text    = sv_text
        self_inner.page_info         = sv_info
    end
end

local orig_fc_init = FileChooser.init
FileChooser.init = function(fc_self)
    fc_self.show_parent_dir = false
    fc_self.height = _contentH()
    orig_fc_init(fc_self)
    if not CFG.show_pagination then
        pcall(function()
            local content = fc_self[1] and fc_self[1][1]
            if content then
                for i = #content, 1, -1 do
                    if content[i] ~= fc_self.content_group then
                        table.remove(content, i)
                    end
                end
            end
        end)
        installRecalcOverride(fc_self)
        fc_self:_recalculateDimen()
    end
    if fc_self.dimen then fc_self.dimen.h = _contentH() end
    pcall(function() fc_self:updateItems() end)
end

local orig_changeToPath = FileChooser.changeToPath
if orig_changeToPath then
    FileChooser.changeToPath = function(fc_self, path, focused_path)
        local h = _contentH()
        fc_self.height = h
        if fc_self.dimen then fc_self.dimen.h = h end
        return orig_changeToPath(fc_self, path, focused_path)
    end
end

local FileManager      = require("apps/filemanager/filemanager")
local orig_setupLayout = FileManager.setupLayout

FileManager.setupLayout = function(fm_self)
    fm_ref = fm_self

    local TitleBar    = require("ui/widget/titlebar")
    local orig_tb_new = TitleBar.new
    TitleBar.new = function(cls, attrs, ...)
        if attrs and attrs.right_icon_tap_callback then
            fm_context_menu_cb = attrs.right_icon_tap_callback
        end
        if attrs then
            if CFG.titlebar then
                attrs = {
                    title           = "",
                    title_h_padding = attrs.title_h_padding,
                    titlebar_height = attrs.titlebar_height,
                }
            else
                attrs = { title = "" }
            end
        end
        return orig_tb_new(cls, attrs, ...)
    end

    orig_setupLayout(fm_self)
    TitleBar.new = orig_tb_new

    if CFG.titlebar then
        UIManager:nextTick(function() _nbUpdateStatusBar(fm_self) end)
    else
        pcall(function()
            local tb = fm_self.title_bar
            if not tb then return end
            if tb.dimen then tb.dimen.h = 0; tb.dimen.w = 0 end
            tb.paintTo = function() end
            local function removeTB(w, depth)
                if not w or (depth or 0) > 6 then return end
                if type(w) == "table" then
                    for i = #w, 1, -1 do
                        if w[i] == tb then table.remove(w, i); return end
                        removeTB(w[i], (depth or 0) + 1)
                    end
                end
            end
            removeTB(fm_self[1], 0)
            local fc = fm_self.file_chooser
            if fc then
                fc.header_size = 0
                pcall(function() fc:updateItems() end)
            end
        end)
    end

    local inner = fm_self._navbar_inner or fm_self[1]
    fm_self._navbar_inner = inner

    local c, wrapped, bar = wrapWithNavbar(inner, active_id)
    fm_self._navbar_container = c; fm_self._navbar_bar = bar
    fm_self._navbar_exec_fn   = execute; fm_self[1] = wrapped

    local orig_onShow = fm_self.onShow
    fm_self.onShow = function(this)
        if orig_onShow then orig_onShow(this) end
        UIManager:setDirty(this[1], "ui")
    end

    registerTouchZones(fm_self, execute)

    fm_self.onPathChanged = function(this, new_path)
        local home = G_reader_settings:readSetting("home_dir")
        active_id = (home and normalizePath(new_path or "") == normalizePath(home)) and "home" or nil
        if this._navbar_container then
            replaceBar(this, buildBar(active_id)); UIManager:setDirty(this._navbar_container, "ui")
        end
        if CFG.titlebar then _nbUpdateStatusBar(this) end
    end

    if CFG.titlebar then
        local function _refreshTB() _nbUpdateStatusBar(fm_self) end
        for _, ev in ipairs({ "onNetworkConnected", "onNetworkDisconnected", "onCharging", "onNotCharging", "onResume" }) do
            local orig_ev = fm_self[ev]
            fm_self[ev] = function(this, ...)
                if orig_ev then orig_ev(this, ...) end
                _refreshTB()
            end
        end
    end

    local orig_resize = fm_self.onScreenResize
    fm_self.onScreenResize = function(this, ...)
        _invalidateDimCache()
        if orig_resize then orig_resize(this, ...) end
        UIManager:scheduleIn(0.1, rebuildAll)
    end
end

local FileManagerMenu      = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")

local orig_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
function FileManagerMenu:setUpdateItemTable()
    local function refreshNavbar()
        _invalidateDimCache()
        local fc = fm_ref and fm_ref.file_chooser
        if fc then
            local h = _contentH()
            fc.height = h
            if fc.dimen then fc.dimen.h = h end
            pcall(function() fc:updateItems() end)
        end
        if fm_ref and fm_ref._navbar_inner then
            local c, wrapped, bar = wrapWithNavbar(fm_ref._navbar_inner, active_id)
            fm_ref._navbar_container = c
            fm_ref._navbar_bar       = bar
            fm_ref[1]                = wrapped
            registerTouchZones(fm_ref, fm_ref._navbar_exec_fn)
            UIManager:scheduleIn(0.1, function() UIManager:forceRePaint() end)
        end
    end
    local function refreshTitlebar()
        if fm_ref then _nbUpdateStatusBar(fm_ref) end
    end

    self.menu_items.navbar_settings = {
        text = "Navbar & Status bar",
        sub_item_table = {
            {
                text = "Navbar bar",
                sub_item_table = {
                    {
                        text = "Display mode (restart required)",
                        sub_item_table = {
                            { text = "Icons only",
                              checked_func = function() return CFG.mode == "icons" end,
                              callback = function() CFG.mode = "icons"; _saveSettings() end },
                            { text = "Text only",
                              checked_func = function() return CFG.mode == "text" end,
                              callback = function() CFG.mode = "text"; _saveSettings() end },
                            { text = "Icons and text",
                              checked_func = function() return CFG.mode == "both" end,
                              callback = function() CFG.mode = "both"; _saveSettings() end },
                        },
                    },
                    {
                        text = "Show separator line",
                        checked_func = function() return CFG.navbar_show_separator end,
                        callback = function()
                            CFG.navbar_show_separator = not CFG.navbar_show_separator
                            _saveSettings()
                            refreshNavbar()
                        end,
                    },
                    {
                        text = "Lock home",
                        checked_func = function() return CFG.lock_home end,
                        callback = function()
                            CFG.lock_home = not CFG.lock_home
                            _saveSettings()
                        end,
                    },
                    (#ICON_PACKS > 0) and {
                        text = "Icon pack (restart required)",
                        sub_item_table = (function()
                            local items = {}
                            for _, pack in ipairs(ICON_PACKS) do
                                local p = pack
                                items[#items + 1] = {
                                    text = p,
                                    checked_func = function() return CFG.icons_pack == p end,
                                    callback = function() CFG.icons_pack = p; _saveSettings() end,
                                }
                            end
                            return items
                        end)(),
                    } or {
                        text = "Icon pack (no packs found in patches/tnb-icons/)",
                        enabled = false,
                    },
                },
            },
            {
                text = "Show pagination (restart required)",
                checked_func = function() return CFG.show_pagination end,
                callback = function() CFG.show_pagination = not CFG.show_pagination; _saveSettings() end,
            },
            {
                text = "Status bar",
                sub_item_table = {
                    {
                        text = "Show status bar (restart required)",
                        checked_func = function() return CFG.titlebar end,
                        callback = function() CFG.titlebar = not CFG.titlebar; _saveSettings() end,
                    },
                    {
                        text = "Left side",
                        sub_item_table = {
                            { text = "Clock only",
                              checked_func = function() return CFG.titlebar_left == "clock" end,
                              callback = function() CFG.titlebar_left = "clock"; _saveSettings(); refreshTitlebar() end },
                            { text = "Clock · model / folder",
                              checked_func = function() return CFG.titlebar_left == "info" end,
                              callback = function() CFG.titlebar_left = "info"; _saveSettings(); refreshTitlebar() end },
                        },
                    },
                    {
                        text = "Custom model name",
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local InputDialog = require("ui/widget/inputdialog")
                            local dlg
                            dlg = InputDialog:new{
                                title = "Custom model name",
                                input = CFG.titlebar_custom_model,
                                hint  = Device.model or "KOReader",
                                description = "Displayed on home. Leave empty to use device default.",
                                buttons = {{
                                    { text = "Cancel", id = "close",
                                      callback = function() UIManager:close(dlg) end },
                                    { text = "Set", is_enter_default = true,
                                      callback = function()
                                          CFG.titlebar_custom_model = dlg:getInputText()
                                          UIManager:close(dlg)
                                          _saveSettings()
                                          refreshTitlebar()
                                          if touchmenu_instance then touchmenu_instance:updateItems() end
                                      end },
                                }},
                            }
                            UIManager:show(dlg)
                            dlg:onShowKeyboard()
                        end,
                    },
                    {
                        text = "Show border",
                        checked_func = function() return CFG.titlebar_show_border end,
                        callback = function() CFG.titlebar_show_border = not CFG.titlebar_show_border; _saveSettings(); refreshTitlebar() end,
                    },
                    {
                        text = "WiFi indicator",
                        checked_func = function() return CFG.titlebar_show_wifi end,
                        callback = function() CFG.titlebar_show_wifi = not CFG.titlebar_show_wifi; _saveSettings(); refreshTitlebar() end,
                    },
                    {
                        text = "Frontlight indicator",
                        checked_func = function() return CFG.titlebar_show_frontlight end,
                        callback = function() CFG.titlebar_show_frontlight = not CFG.titlebar_show_frontlight; _saveSettings(); refreshTitlebar() end,
                    },
                    {
                        text = "RAM indicator",
                        checked_func = function() return CFG.titlebar_show_ram end,
                        callback = function() CFG.titlebar_show_ram = not CFG.titlebar_show_ram; _saveSettings(); refreshTitlebar() end,
                    },
                    {
                        text_func = function()
                            return "RAM pattern  —  " .. (CFG.titlebar_ram_pattern or "$k%")
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local InputDialog = require("ui/widget/inputdialog")
                            local dlg
                            dlg = InputDialog:new{
                                title = "RAM display pattern",
                                input = CFG.titlebar_ram_pattern or "$k%",
                                description = "$k  KOReader usage (%)\n$K  KOReader usage (MB)\n$Kg KOReader usage (GB)\n$u  System usage (%)\n$U  System usage (MB)\n$Ug System usage (GB)\n$A  Total RAM (MB)\n$Ag Total RAM (GB)",
                                buttons = {{
                                    { text = "Cancel", id = "close",
                                      callback = function() UIManager:close(dlg) end },
                                    { text = "Set", is_enter_default = true,
                                      callback = function()
                                          local val = dlg:getInputText()
                                          CFG.titlebar_ram_pattern = val ~= "" and val or "$k%"
                                          UIManager:close(dlg)
                                          _saveSettings()
                                          refreshTitlebar()
                                          if touchmenu_instance then touchmenu_instance:updateItems() end
                                      end },
                                }},
                            }
                            UIManager:show(dlg)
                            dlg:onShowKeyboard()
                        end,
                    },
                    {
                        text = "SSH indicator",
                        checked_func = function() return CFG.titlebar_show_ssh end,
                        callback = function() CFG.titlebar_show_ssh = not CFG.titlebar_show_ssh; _saveSettings(); refreshTitlebar() end,
                    },
                    {
                        text = "Battery indicator",
                        checked_func = function() return CFG.titlebar_show_battery end,
                        callback = function() CFG.titlebar_show_battery = not CFG.titlebar_show_battery; _saveSettings(); refreshTitlebar() end,
                    },
                },
            },
        },
    }

    table.insert(FileManagerMenuOrder.filemanager_settings, "navbar_settings")
    orig_setUpdateItemTable(self)
end

local BookList    = require("ui/widget/booklist")
local orig_bl_new = BookList.new
BookList.new = function(class, attrs, ...)
    attrs = attrs or {}
    if not attrs.height and not attrs._navbar_height_reduced then
        attrs.height = _contentH(); attrs._navbar_height_reduced = true
    end
    return orig_bl_new(class, attrs, ...)
end

local orig_uim_show = UIManager.show
UIManager.show = function(um_self, widget, ...)
    local name = widget and widget.name
    if not (name == "history" and widget._navbar_height_reduced and not widget._navbar_injected) then
        return orig_uim_show(um_self, widget, ...)
    end
    widget._navbar_injected = true
    if fm_ref and fm_ref._navbar_container then
        replaceBar(fm_ref, buildBar("continue")); UIManager:setDirty(fm_ref[1], "ui")
    end
    orig_uim_show(um_self, widget, ...)
    local c, wrapped, bar = wrapWithNavbar(widget[1], "continue")
    widget._navbar_container = c; widget._navbar_bar = bar
    widget._navbar_exec_fn   = execute; widget[1] = wrapped
    registerTouchZones(widget, execute)
    UIManager:setDirty(widget[1], "ui")
    local orig_onClose = widget.onClose
    widget.onClose = function(w_self, ...)
        active_id = "home"
        if fm_ref and fm_ref._navbar_container then
            replaceBar(fm_ref, buildBar("home")); UIManager:setDirty(fm_ref._navbar_container, "ui")
        end
        if orig_onClose then return orig_onClose(w_self, ...) end
    end
end
