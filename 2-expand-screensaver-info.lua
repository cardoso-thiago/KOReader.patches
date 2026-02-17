local DataStorage = require("datastorage")
local ReaderUI = require("apps/reader/readerui")
local SQ3 = require("lua-ljsqlite3/init")
local _ = require("gettext")
local BookInfo = require("apps/filemanager/filemanagerbookinfo")
local utf8proc = require("ffi/utf8proc")
local lfs = require("libs/libkoreader-lfs")

local SETTING_KEY = "stats_patch_last_data"
local STATISTICS_DB_PATH = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

local STOP_WORDS_LISTS = {
    ["pt"] = {
        "o", "a", "os", "as", "um", "uma", "uns", "umas",
        "de", "do", "da", "dos", "das",
        "em", "no", "na", "nos", "nas",
        "por", "para", "pelo", "pela",
        "e", "ou", "que", "se", "com"
    },
    ["en"] = {
        "a", "an", "the", 
        "and", "but", "or", "nor", "for", "so", "yet",
        "at", "by", "in", "of", "on", "to", "up", "with"
    }
}

local ACTIVE_EXCEPTIONS = {}
for _, lang_list in pairs(STOP_WORDS_LISTS) do
    for _, word in ipairs(lang_list) do
        ACTIVE_EXCEPTIONS[word] = true
    end
end

local orig_BookInfo_expandString = BookInfo.expandString
local orig_ReaderUI_onClose = ReaderUI.onClose

local function titleCase(str)
    if not str then return "" end
    str = utf8proc.lowercase_dumb(str)
    
    local idx = 0
    return (str:gsub("(%S+)", function(word)
        idx = idx + 1
        if idx > 1 and ACTIVE_EXCEPTIONS[word] then
            return word
        end
        
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
    
    if h > 0 then
        return string.format(_("%dh %dmin"), h, m)
    else
        return string.format(_("%d min"), m)
    end
end

local function getReadTimeToday(id_book)
    if not id_book then return 0 end
    
    local now = os.time()
    local today_struct = os.date("*t", now)
    local start_of_day = os.time({year=today_struct.year, month=today_struct.month, day=today_struct.day, hour=0, min=0, sec=0})

    local conn = SQ3.open(STATISTICS_DB_PATH)
    if not conn then return 0 end
    
    local stmt = conn:prepare("SELECT sum(duration) FROM page_stat WHERE start_time >= ? AND id_book = ?")
    local duration = 0
    
    if stmt then
        stmt:reset():bind(start_of_day, id_book)
        local row = stmt:step()
        if row and row[1] then
            duration = row[1]
        end
        stmt:close()
    end
    
    conn:close()
    return duration
end

local function saveBookData(ui)
    if not ui or not ui.view or not ui.document then return nil end

    if ui.statistics and ui.statistics.save then
        pcall(function() ui.statistics:save() end)
    end

    local data = {}
    
    if ui.statistics then
        data.id_book = ui.statistics.id_curr_book
        data.avg_time = ui.statistics.avg_time
    end
    
    local page = ui.view.state.page
    if page then
        data.pages_left = ui.document:getTotalPagesLeft(page)
        if ui.toc then
            data.chapter = ui.toc:getTocTitleByPage(page)
        end
    end

    if G_reader_settings then
        G_reader_settings:saveSetting(SETTING_KEY, data)
    end
    
    return data
end

ReaderUI.onClose = function(self)
    saveBookData(self)
    if orig_ReaderUI_onClose then
        return orig_ReaderUI_onClose(self)
    end
end

BookInfo.expandString = function(self, str, file, timestamp)
    local result = orig_BookInfo_expandString(self, str, file, timestamp)
    
    if not (result:find("$L", 1, true) or result:find("$H", 1, true) or result:find("$C", 1, true)) then
        return result
    end

    local data = {}
    local ui = self.ui
    if not ui and ReaderUI.instance then ui = ReaderUI.instance end

    if ui and ui.view then
        data = saveBookData(ui) or {}
    else
        if G_reader_settings then
            data = G_reader_settings:readSetting(SETTING_KEY) or {}
        end
    end

    if result:find("$L", 1, true) then
        local duration = getReadTimeToday(data.id_book)
        result = result:gsub("$L", formatDuration(duration))
    end

    if result:find("$H", 1, true) then
        local val = "..."
        if data.avg_time and data.pages_left then 
            val = formatDuration(data.avg_time * data.pages_left) 
        end
        result = result:gsub("$H", val)
    end

    if result:find("$C", 1, true) then
        local chap = "..."
        if data.chapter then chap = titleCase(data.chapter) end
        result = result:gsub("$C", chap)
    end

    return result
end