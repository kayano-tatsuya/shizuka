import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.shizuka.background
import qs.modules.shizuka.bar
import qs.modules.shizuka.cheatsheet
import qs.modules.shizuka.dock
import qs.modules.shizuka.equalizer
import qs.modules.shizuka.lock
import qs.modules.shizuka.mediaControls
import qs.modules.shizuka.notificationPopup
import qs.modules.shizuka.onScreenDisplay
import qs.modules.shizuka.onScreenKeyboard
import qs.modules.shizuka.overview
import qs.modules.shizuka.polkit
import qs.modules.shizuka.settings
import qs.modules.shizuka.regionSelector
import qs.modules.shizuka.screenCorners
import qs.modules.shizuka.screenTranslator
import qs.modules.shizuka.sessionScreen
import qs.modules.shizuka.sidebarLeft
import qs.modules.shizuka.sidebarRight
import qs.modules.shizuka.overlay
import qs.modules.shizuka.verticalBar
import qs.modules.shizuka.wallpaperSelector
import qs.modules.shizuka.desktopMenu
import qs.modules.shizuka.dropover
import qs.modules.shizuka.frame

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { component: Background {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: EqualizerPopup {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: Settings {} }
    PanelLoader { component: DesktopMenu {} }
    PanelLoader { component: DropShelfPanel {} }
    PanelLoader { component: NiriBackdrop {} }
    PanelLoader { component: ScreenFrame {} }
}
