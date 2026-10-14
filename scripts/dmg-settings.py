# dmgbuild settings for the Many Displays DMG window (used by scripts/build-app.sh --dmg).
# The background is drawn by scripts/make-dmg-background.swift; the icon centres here must match
# the slots in that image. Run: dmgbuild -s scripts/dmg-settings.py -D app=<path to .app> "Many Displays" out.dmg
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]

background = "Resources/DMG/background.tiff"  # build-app.sh runs from the repo root
window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 112
text_size = 13
label_pos = "bottom"
icon_locations = {
    app_name: (170, 200),
    "Applications": (470, 200),
}
