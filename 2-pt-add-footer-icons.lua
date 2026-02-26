local userpatch = require("userpatch")
local logger = require("logger")

local SHOW_KOREADER_RAM = true
local SHOW_SYSTEM_RAM   = true
local SHOW_SSH_STATUS   = true

local SEP      = " · "
local ICON_RAM = ""
local SSH_ON   = ""
local SSH_OFF  = ""

local _patched = false

local function getFooterExtras()
    local parts = {}
    local mem_total, mem_available
    local koreader_rss_kb, koreader_rss_mb

    if SHOW_KOREADER_RAM or SHOW_SYSTEM_RAM then
        if SHOW_KOREADER_RAM then
            local statm = io.open("/proc/self/statm", "r")
            if statm then
                local dummy, rss = statm:read("*number", "*number")
                statm:close()
                if rss then
                    koreader_rss_kb = rss * 4
                    koreader_rss_mb = math.floor(koreader_rss_kb / 1024)
                end
            end
        end

        local f = io.open("/proc/meminfo", "r")
        if f then
            for line in f:lines() do
                if line:find("MemTotal:") then
                    mem_total = tonumber(line:match("%d+"))
                elseif line:find("MemAvailable:") then
                    mem_available = tonumber(line:match("%d+"))
                end
                if mem_total and mem_available then break end
            end
            f:close()
        end

        if mem_total and mem_total > 0 then
            local ram_strings = {}

            if SHOW_KOREADER_RAM and koreader_rss_kb then
                local ko_pct_val = math.floor((koreader_rss_kb / mem_total) * 100)
                local ko_pct_str = ko_pct_val < 1 and "<1%" or (ko_pct_val .. "%")
                table.insert(ram_strings, ko_pct_str .. " (" .. koreader_rss_mb .. "MB)")
            end

            if SHOW_SYSTEM_RAM and mem_available then
                local sys_used_pct_val = math.floor((mem_total - mem_available) / mem_total * 100)
                local sys_used_pct_str = sys_used_pct_val < 1 and "<1%" or (sys_used_pct_val .. "%")
                table.insert(ram_strings, sys_used_pct_str)
            end

            if #ram_strings > 0 then
                table.insert(parts, ICON_RAM .. " " .. table.concat(ram_strings, " / "))
            end
        end
    end

    if SHOW_SSH_STATUS then
        local ok, PluginLoader = pcall(require, "pluginloader")
        if ok and PluginLoader then
            local ssh = PluginLoader:getPluginInstance("SSH")
            if ssh then
                if ssh:isRunning() then
                    table.insert(parts, SSH_ON)
                elseif SSH_OFF ~= "" then
                    table.insert(parts, SSH_OFF)
                end
            end
        end
    end

    return #parts > 0 and table.concat(parts, SEP) or nil
end

local function patchCoverBrowser(plugin)
    if _patched then return end

    local CoverMenu = require("covermenu")
    local BookInfoManager = require("bookinfomanager")
    local Menu = require("ui/widget/menu")

    if not CoverMenu.updatePageInfo then
        logger.warn("PT-FOOTER: CoverMenu.updatePageInfo not found, aborting patch")
        return
    end

    local orig = CoverMenu.updatePageInfo

    local function patched(self, select_number)
        orig(self, select_number)
        if not BookInfoManager:getSetting("replace_footer_text") then return end
        if not self.cur_folder_text then return end
        local current = self.cur_folder_text.text
        if not current or current == "" then return end
        local extras = getFooterExtras()
        if extras then
            self.cur_folder_text:setText(current .. SEP .. extras)
        end
    end

    CoverMenu.updatePageInfo = patched
    Menu.updatePageInfo = patched
    _patched = true
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
