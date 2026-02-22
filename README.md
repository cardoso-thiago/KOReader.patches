## KOReader Patches

**Personal patches for use with**
<sub>
[<img src="https://raw.githubusercontent.com/koreader/koreader.github.io/master/koreader-logo.png" style="width:8%; height:auto;">](https://github.com/koreader/koreader)
</sub>

### [🞂 confirm-first-open](2-confirm-first-open.lua)

Shows a confirmation dialog **before opening a book for the first time** on the device.

### [🞂 disable-wifi-off-notification](2-disable-wifi-off-notification.lua)

Blocks the "wi-fi off" notification from appearing in the UI by filtering popup messages.

### [🞂 kobo-style-screensaver](2-kobo-style-screensaver.lua)

Renders a custom screensaver displaying book information in Kobo-style layout, including title, chapter, progress, and book cover. Supports dark mode, customizable fonts, and random quote selection from highlights.

> **Based on:** [PedroMachado1/Koreader.patches](https://github.com/PedroMachado1/Koreader.patches/blob/main/2-kobo-style-screensaver.lua)  
> **Focus of modification:** Enhanced wallpaper selection mechanism with support for both directory and file paths.

### [🞂 expand-screensaver-info](2-expand-screensaver-info.lua)

Expands the available text variables for screensavers (and status bar) by injecting custom tokens. Features a caching mechanism that saves the last active book's statistics, allowing variables to display correctly even when the device is suspended from the file manager or main menu.

**Available Tokens**:
- $L: Time read today (e.g., "1h 30min").
- $H: Estimated time left to finish the book based on reading statistics.
- $C: Current chapter title.

### [🞂 pt-no-blank-foldercovers](2--pt-no-blank-foldercovers.lua)

Modifies the folder cover display in Mosaic/Grid view. If a folder contains fewer than 4 books, it removes the empty placeholders/gaps, displaying only the available covers.

> **Based on:** [tmfsd/KOReader-patches](https://github.com/tmfsd/KOReader-patches/blob/main/2-pt-no-blank-foldercovers.lua)  
> **Focus of modification:** Refactored internal function names to match standard KOReader naming conventions (e.g., `build_grid`).  
> **Compatibility Note:** This refactor allows the **Automatic Series Grouping** patch to hook into and inherit this "no-blank" behavior for virtual series folders. **Crucial:** This patch must load *before* the series patch (ensure alphabetical precedence).

### [🞂 wifi-auto-off-monitor](2-wifi-auto-off-monitor.lua)

Monitors WiFi connection and displays a confirmation dialog after 30 seconds of continuous WiFi activity. Allows users to either keep WiFi enabled or turn it off with a single action. The dialog won't appear while the device is in screensaver mode, preventing unnecessary interruptions during sleep.

### [🞂 hide-single-page-nav](2-hide-single-page-nav.lua)

Hides the entire bottom navigation bar (<< < 1 > >>) in the file manager when a folder contains only one page of items.

### [🞂 pt-add-footer-icons](2-pt-add-footer-icons.lua)

Adds new info to the **Project Title** (CoverBrowser) plugin footer.

* **RAM:** Displays memory usage as a percentage.
* **SSH:** The icon only appears when the SSH server is running, hiding when turned off to save space.

**Requirement:** "Footer" > "Device Info" must be enabled in the Project Title settings.
