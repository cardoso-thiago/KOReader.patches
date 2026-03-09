local Menu = require("ui/widget/menu")

local original_updatePageInfo = Menu.updatePageInfo

function Menu:updatePageInfo(...)
    original_updatePageInfo(self, ...)

    local items = self.item_table and #self.item_table or 0
    local perpage = self.perpage or 1
    local total_pages = math.ceil(items / perpage)

    local is_single_page = (total_pages <= 1)

    local nav_items = {
        "page_info_first_chev",
        "page_info_left_chev",
        "page_info_text",
        "page_info_right_chev",
        "page_info_last_chev",
        "page_info_spacer",
        "page_info" 
    }

    for _, item_name in ipairs(nav_items) do
        local widget = self[item_name]
        
        if widget then
            if is_single_page then
                widget.invisible = true
                
                if not widget.original_paintTo then
                    widget.original_paintTo = widget.paintTo
                end
                widget.paintTo = function() end
            else
                widget.invisible = false
                
                if widget.original_paintTo then
                    widget.paintTo = widget.original_paintTo
                    widget.original_paintTo = nil
                end
            end
        end
    end
end

return Menu
