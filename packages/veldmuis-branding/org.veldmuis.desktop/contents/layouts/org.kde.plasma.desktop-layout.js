var panel = new Panel
var panelScreen = panel.screen

panel.height = 2 * Math.ceil(gridUnit * 2.5 / 2)

const maximumAspectRatio = 21 / 9
if (panel.formFactor === "horizontal") {
    const geo = screenGeometry(panelScreen)
    const maximumWidth = Math.ceil(geo.height * maximumAspectRatio)

    if (geo.width > maximumWidth) {
        panel.alignment = "center"
        panel.minimumLength = maximumWidth
        panel.maximumLength = maximumWidth
    }
}

var kickoff = panel.addWidget("org.kde.plasma.kickoff")
kickoff.currentConfigGroup = ["General"]
kickoff.writeConfig("alphaSort", "true")
kickoff.writeConfig("favoritesDisplay", "1")
kickoff.writeConfig("switchCategoryOnHover", "true")
kickoff.writeConfig("systemFavorites", "suspend\\,hibernate\\,reboot\\,shutdown")

var tasks = panel.addWidget("org.kde.plasma.icontasks")
tasks.currentConfigGroup = ["General"]
tasks.writeConfig("launchers", "")

panel.addWidget("org.kde.plasma.marginsseparator")

var systemTray = panel.addWidget("org.kde.plasma.systemtray")
systemTray.currentConfigGroup = ["General"]
systemTray.writeConfig("extraItems", "org.kde.plasma.printmanager,org.kde.plasma.brightness,org.kde.plasma.cameraindicator,org.kde.plasma.volume,org.kde.plasma.battery,org.kde.plasma.devicenotifier,org.kde.plasma.keyboardlayout,org.kde.plasma.manage-inputmethod,org.kde.plasma.keyboardindicator,org.kde.plasma.mediacontroller,org.kde.kscreen,org.kde.plasma.bluetooth,org.kde.plasma.diskquota,org.kde.plasma.notifications,org.kde.plasma.networkmanagement")
systemTray.writeConfig("hiddenItems", "org.kde.plasma.brightness,org.kde.plasma.cameraindicator,org.kde.plasma.devicenotifier,org.kde.kscreen,org.kde.plasma.keyboardlayout,org.kde.plasma.keyboardindicator,org.kde.plasma.printmanager,org.kde.plasma.manage-inputmethod,org.kde.plasma.mediacontroller,org.kde.plasma.diskquota,org.kde.plasma.notifications")
systemTray.writeConfig("knownItems", "org.kde.plasma.networkmanagement,org.kde.plasma.printmanager,org.kde.plasma.brightness,org.kde.plasma.cameraindicator,org.kde.plasma.notifications,org.kde.plasma.volume,org.kde.plasma.battery,org.kde.plasma.devicenotifier,org.kde.plasma.keyboardlayout,org.kde.plasma.vault,org.kde.plasma.manage-inputmethod,org.kde.plasma.keyboardindicator,org.kde.plasma.mediacontroller,org.kde.plasma.clipboard,org.kde.kscreen,org.kde.plasma.bluetooth,org.kde.plasma.weather")
systemTray.writeConfig("shownItems", "org.kde.plasma.volume,org.kde.plasma.networkmanagement,org.kde.plasma.bluetooth,org.kde.plasma.battery")

panel.addWidget("org.kde.plasma.digitalclock")

var desktopsArray = desktopsForActivity(currentActivity())
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image"
    desktopsArray[j].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"]
    desktopsArray[j].writeConfig("Image", "/usr/share/wallpapers/VeldmuisDawn/contents/images/1920x1080.png")
}
