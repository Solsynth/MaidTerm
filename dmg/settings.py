"""dmgbuild settings for the MaidTerm installer image."""

import os.path
import plistlib

application = defines["app"]
appname = os.path.basename(application)


def icon_from_app(app_path):
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    with open(plist_path, "rb") as file:
        plist = plistlib.load(file)
    icon_name = plist["CFBundleIconFile"]
    icon_root, icon_ext = os.path.splitext(icon_name)
    if not icon_ext:
        icon_ext = ".icns"
    return os.path.join(
        app_path,
        "Contents",
        "Resources",
        icon_root + icon_ext,
    )


format = defines.get("format", "UDBZ")
size = defines.get("size", None)
files = [application]
symlinks = {"Applications": "/Applications"}
badge_icon = icon_from_app(application)
icon_locations = {appname: (140, 120), "Applications": (500, 120)}
background = "#f1a39c"

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 180

window_rect = ((100, 100), (640, 280))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = "auto"

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 16
icon_size = 128
