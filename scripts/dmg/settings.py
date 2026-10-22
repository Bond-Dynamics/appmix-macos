# dmgbuild settings for the AppMix installer window: the app on the left, an Applications
# shortcut on the right, and a background arrow between them. Passed in with -D:
#   app=<path to AppMix.app>  background=<path to background.tiff>  icon=<path to AppIcon.icns>
# Icon positions are Finder points from the window's top-left and must match make-background.swift.
import os.path

app = defines["app"]
app_name = os.path.basename(app)

format = "ULFO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

window_rect = ((200, 120), (640, 400))
default_view = "icon-view"
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (170, 190),
    "Applications": (470, 190),
}
