local DataStorage = require("datastorage")
local ReaderUI = require("apps/reader/readerui")
local SQ3 = require("lua-ljsqlite3/init")
local _ = require("gettext")
local BookInfo = require("apps/filemanager/filemanagerbookinfo")
local utf8proc = require("ffi/utf8proc")

local SETTING_KEY = "stats_patch_last_data"
local STATISTICS_DB_PATH = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

local STOP_WORDS_LISTS = {
    ["pt"] = {
        "o", "a", "os", "as", "um", "uma", "uns", "umas",
        "de", "do", "da", "dos", "das", "em", "no", "na", "nos", "nas",
        "por", "para", "pelo", "pela", "e", "ou", "que", "se", "com"
    },
    ["en"] = {
        "a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet",
        "at", "by", "in", "of", "on", "to", "up", "with"
    }
}

local ACTIVE_EXCEPTIONS = {}
for _, lang_list in pairs(STOP_WORDS_LISTS) do
    for _, word in ipairs(lang_list) do ACTIVE_EXCEPTIONS[word] = true end
end

local orig_BookInfo_expandString = BookInfo.expandString
local orig_ReaderUI_onClose = ReaderUI.onClose

local function titleCase(str)
    if not str or str == "" then return "" end
    str = utf8proc.lowercase_dumb(str)
    local idx = 0
    return (str:gsub("(%S+)", function(word)
        idx = idx + 1
        if idx > 1 and ACTIVE_EXCEPTIONS[word] then return word end
        local b = word:byte(1)
        local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
        return utf8proc.uppercase_dumb(word:sub(1, len)) .. word:sub(len + 1)
    end))
end

local function formatDuration(secs)
    local s = tonumber(secs) or 0
    if s <= 0 then return _("0 min") end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h > 0 then return string.format(_("%dh %dmin"), h, m)
    else return string.format(_("%d min"), m) end
end

local function getReadTimeToday(id_book)
    if not id_book then return 0 end
    local now = os.time()
    local t = os.date("*t", now)
    local start_today = os.time({year=t.year, month=t.month, day=t.day, hour=0, min=0, sec=0})

    local ok, conn = pcall(SQ3.open, STATISTICS_DB_PATH)
    if not ok or not conn then return 0 end

    local sql = string.format([[
        SELECT sum(duration) FROM page_stat 
        WHERE start_time >= %d AND id_book = %d
    ]], start_today, id_book)

    local duration = 0
    pcall(function()
        local row = conn:rowexec(sql)
        duration = tonumber(row) or 0
    end)
    conn:close()
    return duration
end

local function updateAndSaveData(ui)
    if not ui or not ui.view or not ui.document then return nil end

    if ui.statistics and ui.statistics.insertDB then
        pcall(ui.statistics.insertDB, ui.statistics)
    end

    local data = {
        id_book = ui.statistics and ui.statistics.id_curr_book,
        avg_time = ui.statistics and ui.statistics.avg_time,
        pages_left = ui.document:getTotalPagesLeft(ui.view.state.page),
        chapter = ui.toc and ui.toc:getTocTitleByPage(ui.view.state.page)
    }

    if G_reader_settings then
        G_reader_settings:saveSetting(SETTING_KEY, data)
    end
    return data
end

ReaderUI.onClose = function(self)
    updateAndSaveData(self)
    if orig_ReaderUI_onClose then return orig_ReaderUI_onClose(self) end
end

BookInfo.expandString = function(self, str, file, timestamp)
    local result = orig_BookInfo_expandString(self, str, file, timestamp)
    if not (result:find("$L", 1, true) or result:find("$H", 1, true) or result:find("$C", 1, true)) then
        return result
    end

    local ui = self.ui or ReaderUI.instance
    local data

    if ui and ui.view and ui.view.state then
        data = updateAndSaveData(ui)
    else
        data = G_reader_settings and G_reader_settings:readSetting(SETTING_KEY) or {}
    end

    if result:find("$L", 1, true) then
        result = result:gsub("$L", formatDuration(getReadTimeToday(data.id_book)))
    end

    if result:find("$H", 1, true) then
        local val = "..."
        if data.avg_time and data.pages_left then val = formatDuration(data.avg_time * data.pages_left) end
        result = result:gsub("$H", val)
    end

    if result:find("$C", 1, true) then
        result = result:gsub("$C", titleCase(data.chapter) or "...")
    end

    return result
end