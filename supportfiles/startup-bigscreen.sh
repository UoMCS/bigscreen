#!/bin/sh

# Remove any config and cache files to prevent problems with caching
rm -rf ~/.config/chromium
rm -rf ~/.cache/chromium

# And now start the browser itself
/usr/bin/chromium-browser --noerrdialogs --disable-session-crashed-bubble --disable-infobars --kiosk http://URL.HERE
