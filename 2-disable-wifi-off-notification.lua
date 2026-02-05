local UIManager = require("ui/uimanager")

local old_show = UIManager.show

local text_to_block = "wi-fi off." 

UIManager.show = function(self, widget, ...)
    if widget then
        local content = widget.text

        if type(content) == "string" then
            if content:lower():find(text_to_block, 1, true) then
                return
            end
        end
    end

    return old_show(self, widget, ...)
end