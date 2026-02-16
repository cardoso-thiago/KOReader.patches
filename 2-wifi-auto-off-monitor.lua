local logger = require("logger")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local Notification = require("ui/widget/notification")
local Device = require("device")
local _ = require("gettext")
local NetworkMgr = require("ui/network/manager")
local PluginLoader = require("pluginloader")
local SpinWidget = require("ui/widget/spinwidget")

local CONFIG = {
    check_interval = 30,
    snooze_default_value = 1,
    snooze_max_minutes = 15,
    handle_ssh = true,
}

if not NetworkMgr._wifi_monitor_patched then
    NetworkMgr._wifi_monitor_patched = true
    
    local WiFiMonitor = {
        is_monitoring = false,
        wifi_timer = nil,
        dialog_showing = false,
        current_dialog = nil,
        snooze_timer = nil,
        is_snoozed = false,
    }
    
    local original_turnOnWifi = NetworkMgr.turnOnWifi
    local original_turnOffWifi = NetworkMgr.turnOffWifi
    
    if not original_turnOnWifi then logger.error("[WiFiMonitor] CRITICAL: turnOnWifi nil") end
    if not original_turnOffWifi then logger.error("[WiFiMonitor] CRITICAL: turnOffWifi nil") end

    local function getSSHPlugin()
        if not PluginLoader then return nil end
        return PluginLoader:getPluginInstance("SSH")
    end
    
    function WiFiMonitor:stopSSHIfRunning()
        local ssh_plugin = getSSHPlugin()
        if ssh_plugin and ssh_plugin:isRunning() then
            logger.dbg("[WiFiMonitor] Stopping SSH server...")
            ssh_plugin:stop()
            return true
        end
        return false
    end
    
    function WiFiMonitor:startWiFiTimer()
        if not WiFiMonitor.is_monitoring then return end
        
        if WiFiMonitor.wifi_timer then
            UIManager:unschedule(WiFiMonitor.wifi_timer)
            WiFiMonitor.wifi_timer = nil
        end
        
        WiFiMonitor.wifi_timer = UIManager:scheduleIn(CONFIG.check_interval, function()
            WiFiMonitor:checkWiFiStatusAndNotify()
        end)
    end
    
    function WiFiMonitor:checkWiFiStatusAndNotify()
        if not NetworkMgr then return end
        
        local wifi_on = NetworkMgr:isWifiOn()
        
        if not wifi_on then
            WiFiMonitor.is_monitoring = false
            WiFiMonitor.wifi_timer = nil
            return
        end
        
        if WiFiMonitor.is_snoozed then
            logger.dbg("[WiFiMonitor] WiFi is snoozed, skipping check")
            return
        end
        
        if not WiFiMonitor.dialog_showing then
            self:showTimeoutDialog()
        end
    end
    
    function WiFiMonitor:showSnoozePickerDialog()
        if Device.screen_saver_mode then
            return
        end
        
        local snooze_confirmed = false
        
        local snooze_widget = SpinWidget:new{
            title_text = _("WiFi Snooze"),
            info_text = _("Select snooze duration in minutes"),
            width = math.floor(math.min(Device.screen:getWidth(), Device.screen:getHeight()) * 0.6),
            value = CONFIG.snooze_default_value,
            value_min = 1,
            value_max = CONFIG.snooze_max_minutes,
            value_step = 1,
            value_hold_step = 1,
            unit = _("min"),
            ok_text = _("Snooze"),
            cancel_text = _("Cancel"),
            ok_always_enabled = true,
            callback = function(snooze_spin)
                snooze_confirmed = true
                local snooze_minutes = snooze_spin.value
                local snooze_seconds = snooze_minutes * 60
                
                logger.dbg(string.format("[WiFiMonitor] WiFi snoozed for %d minutes", snooze_minutes))
                
                WiFiMonitor.is_snoozed = true
                
                if WiFiMonitor.snooze_timer then
                    UIManager:unschedule(WiFiMonitor.snooze_timer)
                end
                
                WiFiMonitor.snooze_timer = UIManager:scheduleIn(snooze_seconds, function()
                    WiFiMonitor.is_snoozed = false
                    WiFiMonitor.snooze_timer = nil
                    logger.dbg("[WiFiMonitor] Snooze ended, resuming WiFi checks")
                    if WiFiMonitor.is_monitoring then
                        WiFiMonitor:checkWiFiStatusAndNotify()
                    end
                end)
                
                UIManager:show(Notification:new{
                    text = string.format(_("WiFi checks snoozed for %d minute(s)"), snooze_minutes),
                    timeout = 2,
                })
            end,
            cancel_callback = function()
                logger.dbg("[WiFiMonitor] Snooze cancelled, returning to WiFi dialog")
                WiFiMonitor:showTimeoutDialog()
            end,
            close_callback = function()
                if not snooze_confirmed then
                    logger.dbg("[WiFiMonitor] Snooze picker closed, returning to WiFi dialog")
                    WiFiMonitor:showTimeoutDialog()
                end
            end,
        }
        UIManager:show(snooze_widget)
    end
    
    function WiFiMonitor:showTimeoutDialog()
        if Device.screen_saver_mode then
            if WiFiMonitor.is_monitoring then
                WiFiMonitor:startWiFiTimer()
            end
            return
        end
        
        if WiFiMonitor.dialog_showing then return end
        
        WiFiMonitor.dialog_showing = true

        local text_msg = string.format(_("WiFi has been on for more than %d seconds.\n\nDo you want to keep WiFi on or turn it off?"), CONFIG.check_interval)
        
        local ssh_plugin = getSSHPlugin()
        if CONFIG.handle_ssh and ssh_plugin and ssh_plugin:isRunning() then
            text_msg = text_msg .. "\n\n" .. _("(SSH Server is running and will be stopped)")
        end
        
        local dialog
        dialog = ConfirmBox:new{
            title = _("WiFi Auto-Off Monitor"),
            text = text_msg,
            ok_text = _("Keep On"),
            cancel_text = _("Turn Off"),
            dismissable = false,
            other_buttons = {{
                {
                    text = _("Snooze"),
                    callback = function()
                        WiFiMonitor.dialog_showing = false
                        WiFiMonitor.current_dialog = nil
                        if dialog then UIManager:close(dialog) end
                        WiFiMonitor:showSnoozePickerDialog()
                    end,
                }
            }},
            other_buttons_first = true,
            ok_callback = function()
                WiFiMonitor.dialog_showing = false
                WiFiMonitor.current_dialog = nil
                if dialog then UIManager:close(dialog) end
                
                WiFiMonitor:startWiFiTimer()
            end,
            cancel_callback = function()
                WiFiMonitor.dialog_showing = false
                WiFiMonitor.current_dialog = nil
                if dialog then UIManager:close(dialog) end
                
                WiFiMonitor.is_monitoring = false
                
                if CONFIG.handle_ssh then
                    WiFiMonitor:stopSSHIfRunning()
                end
                
                if original_turnOffWifi then
                    original_turnOffWifi(NetworkMgr, function()
                        UIManager:show(Notification:new{
                            text = _("WiFi turned off"),
                            timeout = 2,
                        })
                    end)
                end
            end,
        }
        
        WiFiMonitor.current_dialog = dialog
        UIManager:show(dialog)
    end
    
    function NetworkMgr:turnOnWifi(complete_callback, interactive)
        WiFiMonitor.dialog_showing = false
        WiFiMonitor.is_snoozed = false
        
        if WiFiMonitor.wifi_timer then
            UIManager:unschedule(WiFiMonitor.wifi_timer)
            WiFiMonitor.wifi_timer = nil
        end
        
        if WiFiMonitor.snooze_timer then
            UIManager:unschedule(WiFiMonitor.snooze_timer)
            WiFiMonitor.snooze_timer = nil
        end
        
        if WiFiMonitor.current_dialog then
            UIManager:close(WiFiMonitor.current_dialog)
            WiFiMonitor.current_dialog = nil
        end
        
        UIManager:scheduleIn(2, function()
            WiFiMonitor.is_monitoring = true
            WiFiMonitor:startWiFiTimer()
        end)
        
        if original_turnOnWifi then
            return original_turnOnWifi(self, complete_callback, interactive)
        end
    end
    
    function NetworkMgr:turnOffWifi(complete_callback)
        WiFiMonitor.is_monitoring = false
        WiFiMonitor.is_snoozed = false
        
        if WiFiMonitor.wifi_timer then
            UIManager:unschedule(WiFiMonitor.wifi_timer)
            WiFiMonitor.wifi_timer = nil
        end
        
        if WiFiMonitor.snooze_timer then
            UIManager:unschedule(WiFiMonitor.snooze_timer)
            WiFiMonitor.snooze_timer = nil
        end
        
        if WiFiMonitor.dialog_showing and WiFiMonitor.current_dialog then
            UIManager:close(WiFiMonitor.current_dialog)
            WiFiMonitor.dialog_showing = false
            WiFiMonitor.current_dialog = nil
        end
        
        if original_turnOffWifi then
            return original_turnOffWifi(self, complete_callback)
        end
    end

    if NetworkMgr:isWifiOn() then
        logger.info("[WiFiMonitor] WiFi is ON at startup, starting monitor")
        WiFiMonitor.is_monitoring = true
        WiFiMonitor:startWiFiTimer()
    end
end

return true