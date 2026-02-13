--[[--
WiFi Auto-Off Monitor Patch

This patch monitors WiFi usage and displays a dialog after 30 seconds of continuous WiFi activity,
asking the user whether to keep WiFi on or turn it off.

Usage:
Simply leave this patch enabled. When WiFi stays on for 30+ seconds,
a notification dialog will appear asking if you want to keep it on.
--]]--

local logger = require("logger")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local Notification = require("ui/widget/notification")
local Device = require("device")
local _ = require("gettext")
local NetworkMgr = require("ui/network/manager")

if not NetworkMgr._wifi_monitor_patched then
    NetworkMgr._wifi_monitor_patched = true
    
    local WiFiMonitor = {
        is_monitoring = false,
        wifi_timer = nil,
        dialog_showing = false,
        dialog_timer = nil,
        wifi_turn_on_time = nil,
        current_dialog = nil,
        wifi_was_on = false,
    }
    
    local original_turnOnWifi = NetworkMgr.turnOnWifi
    local original_turnOffWifi = NetworkMgr.turnOffWifi
    
    if not original_turnOnWifi then
        logger.error("[WiFiMonitor] CRITICAL: original_turnOnWifi is nil!")
    end
    if not original_turnOffWifi then
        logger.error("[WiFiMonitor] CRITICAL: original_turnOffWifi is nil!")
    end
    
    function WiFiMonitor:startWiFiTimer()
        if not WiFiMonitor.is_monitoring then
            return
        end
        
        if WiFiMonitor.wifi_timer then
            UIManager:unschedule(WiFiMonitor.wifi_timer)
            WiFiMonitor.wifi_timer = nil
        end
        
        WiFiMonitor.wifi_timer = UIManager:scheduleIn(30, function()
            WiFiMonitor:checkWiFiStatusAndNotify()
        end)
    end
    
    function WiFiMonitor:checkWiFiStatusAndNotify()
        if not NetworkMgr then
            logger.error("[WiFiMonitor] NetworkMgr is nil!")
            return
        end
        
        local wifi_on = NetworkMgr:isWifiOn()
        
        if not wifi_on then
            WiFiMonitor.is_monitoring = false
            WiFiMonitor.wifi_timer = nil
            return
        end
        
        if not WiFiMonitor.dialog_showing then
            self:showTimeoutDialog()
        end
    end
    
    function WiFiMonitor:showTimeoutDialog()
        if Device.screen_saver_mode then
            if WiFiMonitor.is_monitoring then
                WiFiMonitor:startWiFiTimer()
            end
            return
        end
        
        if WiFiMonitor.dialog_showing then
            return
        end
        
        WiFiMonitor.dialog_showing = true
        
        local dialog
        dialog = ConfirmBox:new{
            title = _("WiFi Auto-Off Monitor"),
            text = _("WiFi has been on for more than 30 seconds.\n\n"
                     .. "Do you want to keep WiFi on or turn it off?"),
            ok_text = _("Keep On"),
            cancel_text = _("Turn Off"),
            ok_callback = function()
                WiFiMonitor.dialog_showing = false
                WiFiMonitor.current_dialog = nil
                
                if dialog then
                    UIManager:close(dialog)
                end
                
                WiFiMonitor.wifi_turn_on_time = os.time()
                WiFiMonitor:startWiFiTimer()
            end,
            cancel_callback = function()
                WiFiMonitor.dialog_showing = false
                WiFiMonitor.current_dialog = nil
                
                if dialog then
                    UIManager:close(dialog)
                end
                
                if original_turnOffWifi then
                    original_turnOffWifi(NetworkMgr, function()
                        UIManager:show(Notification:new{
                            text = _("WiFi turned off"),
                            timeout = 2,
                        })
                    end)
                else
                    logger.error("[WiFiMonitor] original_turnOffWifi is nil!")
                end
            end,
        }
        
        WiFiMonitor.current_dialog = dialog
        UIManager:show(dialog)
    end
    
    function NetworkMgr:turnOnWifi(complete_callback, interactive)
        WiFiMonitor.dialog_showing = false
        WiFiMonitor.wifi_turn_on_time = os.time()
        WiFiMonitor.wifi_was_on = true
        
        if WiFiMonitor.wifi_timer then
            UIManager:unschedule(WiFiMonitor.wifi_timer)
            WiFiMonitor.wifi_timer = nil
        end
        
        if WiFiMonitor.current_dialog then
            UIManager:close(WiFiMonitor.current_dialog)
            WiFiMonitor.current_dialog = nil
            WiFiMonitor.dialog_showing = false
        end
        
        UIManager:scheduleIn(2, function()
            if not WiFiMonitor.is_monitoring then
                WiFiMonitor.is_monitoring = true
                WiFiMonitor:startWiFiTimer()
            end
        end)
        
        if original_turnOnWifi then
            return original_turnOnWifi(self, complete_callback, interactive)
        else
            logger.error("[WiFiMonitor] original_turnOnWifi is nil!")
        end
    end
    
    function NetworkMgr:turnOffWifi(complete_callback)
        WiFiMonitor.is_monitoring = false
        WiFiMonitor.wifi_turn_on_time = nil
        WiFiMonitor.wifi_was_on = false
        
        if WiFiMonitor.wifi_timer then
            UIManager:unschedule(WiFiMonitor.wifi_timer)
            WiFiMonitor.wifi_timer = nil
        end
        
        if WiFiMonitor.dialog_showing and WiFiMonitor.current_dialog then
            UIManager:close(WiFiMonitor.current_dialog)
            WiFiMonitor.dialog_showing = false
            WiFiMonitor.current_dialog = nil
        end
        
        if original_turnOffWifi then
            return original_turnOffWifi(self, complete_callback)
        else
            logger.error("[WiFiMonitor] original_turnOffWifi is nil!")
        end
    end
end

return true
