local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local BookInfo = require("apps/filemanager/filemanagerbookinfo")
local ReaderUI = require("apps/reader/readerui")
local utf8proc = require("ffi/utf8proc")

local SETTING_KEY = "stats_patch_last_data"
local STATISTICS_DB_PATH = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

local function titleCase(str)
    if not str then return str end

    str = utf8proc.lowercase_dumb(str)

    return (str:gsub("(%S)(%S*)", function(first, rest)
        return utf8proc.uppercase_dumb(first) .. rest
    end))
end


local function formatDuration(secs)
    local s = tonumber(secs)
    if not s or s <= 0 then return _("0 min") end
    
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    
    if h > 0 and m > 0 then
        return string.format(_("%dh %dmin"), h, m)
    elseif h > 0 then
        return string.format(_("%dh"), h)
    elseif m > 0 then
        return string.format(_("%d min"), m)
    else
        return _("< 1 min")
    end
end

local function getBookTodayDurationById(id_book)
    if not id_book or not STATISTICS_DB_PATH then return nil end
    local attrs = lfs.attributes(STATISTICS_DB_PATH, "mode")
    if attrs ~= "file" then return nil end
    
    local now_stamp = os.time()
    local now_t = os.date("*t", now_stamp)
    local start_today_time = now_stamp - (now_t.hour * 3600 + now_t.min * 60 + now_t.sec)
    
    local ok_conn, conn = pcall(SQ3.open, STATISTICS_DB_PATH)
    if not ok_conn or not conn then return nil end
    
    local sql_stmt = string.format([[SELECT sum(sum_duration)
        FROM (
            SELECT sum(duration) AS sum_duration
            FROM page_stat
            WHERE start_time >= %d AND id_book = %d
            GROUP BY page
        );
    ]], start_today_time, id_book)
    
    local ok_row, today_duration = pcall(function()
        return conn:rowexec(sql_stmt)
    end)
    
    if conn then conn:close() end
    if not ok_row or today_duration == nil then return nil end
    return tonumber(today_duration)
end

local function updateSavedData(ui)
    if not ui or not ui.view or not ui.view.state or not ui.document then return end

    local data = {}
    
    if ui.statistics then
        if ui.statistics.insertDB then pcall(ui.statistics.insertDB, ui.statistics) end
        data.id_book = ui.statistics.id_curr_book
        data.avg_time = ui.statistics.avg_time
    end
    
    local page = ui.view.state.page
    if page then
        data.pages_left = ui.document:getTotalPagesLeft(page)
    end

    if ui.toc then
        data.chapter = ui.toc:getTocTitleByPage(page)
    end

    G_reader_settings:saveSetting(SETTING_KEY, data)
end

local function loadSavedData()
    return G_reader_settings:readSetting(SETTING_KEY)
end

local orig_BookInfo_expandString = BookInfo.expandString

BookInfo.expandString = function(self, str, file, timestamp)
    if self == nil then 
        return orig_BookInfo_expandString(self, str, file, timestamp) 
    end

    local result = orig_BookInfo_expandString(self, str, file, timestamp)

    if str:find("$L") or str:find("$H") or str:find("$C") then
        local ui = self.ui
        if not ui then ui = ReaderUI.instance end

        local is_active = (ui and ui.view and ui.view.state)
        local current_data = {}

        if is_active then
            updateSavedData(ui)
            
            if ui.statistics then 
                current_data.id_book = ui.statistics.id_curr_book 
                current_data.avg_time = ui.statistics.avg_time
            end

            local page = ui.view.state.page
            if page and ui.document then
                current_data.pages_left = ui.document:getTotalPagesLeft(page)
            end
            if ui.toc then
                current_data.chapter = ui.toc:getTocTitleByPage(page)
            end
        else
            current_data = loadSavedData() or {}
        end

        if str:find("$L") then
            local time_read_today = _("0 min")
            if current_data.id_book then
                local duration = getBookTodayDurationById(current_data.id_book)
                if duration then
                    time_read_today = formatDuration(duration)
                end
            end
            result = result:gsub("$L", time_read_today)
        end

        if str:find("$H") then
            local time_left_formatted = "N/A"
            if current_data.avg_time and current_data.pages_left then
                local total_secs = current_data.avg_time * current_data.pages_left
                time_left_formatted = formatDuration(total_secs)
            elseif not current_data.avg_time then
                 time_left_formatted = "..."
            end
            result = result:gsub("$H", time_left_formatted)
        end

        if str:find("$C") then
            local chapter_text = "N/A"
            if current_data.chapter and current_data.chapter ~= "" then
                chapter_text = titleCase(current_data.chapter)
            end
            result = result:gsub("$C", chapter_text)
        end
    end

    return result
end