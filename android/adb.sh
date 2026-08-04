

# Connect your device and test
adb devices

# Find the package name
adb shell pm list packages
adb shell pm list packages | grep appname


# Remove user installed app
adb uninstall com.example.myapp

# Remove a preinstalled/system app for current user
adb shell pm uninstall --user 0 com.example.myapp

# Disable a system app instead
adb shell pm disable-user --user 0 com.example.myapp

# Reinstall a system app you removed/disabled for user 0
adb shell cmd package install-existing com.example.myapp



# List third-party (user-installed) apps:
adb shell pm list packages -3

# List system apps:
adb shell pm list packages -s

# Show package names with APK paths:
adb shell pm list packages -f


###################################################
# Remove apps from samsung phone
###################################################
adb shell pm uninstall --user 0 com.netflix.partner.activation
adb shell pm uninstall --user 0 com.netflix.mediaclient
adb shell pm uninstall --user 0 com.google.android.projection.gearhead
adb shell pm uninstall --user 0 com.google.android.apps.tachyon
adb shell pm uninstall --user 0 com.samsung.android.app.spage
adb shell pm uninstall --user 0 com.samsung.android.visionintelligence
adb shell pm uninstall --user 0 com.samsung.android.bixbyvision.framework
adb shell pm uninstall --user 0 com.facebook.appmanager com.facebook.system com.facebook.services
adb shell pm uninstall --user 0 com.facebook.appmanager
adb shell pm uninstall --user 0 com.facebook.system
adb shell pm uninstall --user 0 com.facebook.services
adb shell pm uninstall --user 0 com.microsoft.skydrive
adb shell pm uninstall --user 0 com.microsoft.appmanager
adb shell pm uninstall --user 0 com.opera.max.oem
adb shell pm uninstall --user 0 com.google.android.as
adb shell pm uninstall --user 0 com.google.android.as.oss
adb shell pm uninstall --user 0 com.samsung.android.aliveprivacy
adb shell pm uninstall --user 0 com.samsung.ecomm.global.in
adb shell pm uninstall --user 0 com.sec.android.daemonapp
adb shell pm uninstall --user 0 com.android.chrome
adb shell pm uninstall --user 0 com.mygalaxy
adb shell pm uninstall --user 0 com.google.android.gm
adb shell pm uninstall --user 0 com.google.android.tts
adb shell pm uninstall --user 0 com.google.android.youtube
adb shell pm uninstall --user 0 com.samsung.android.honeyboard
adb shell pm uninstall --user 0 com.samsung.android.video
adb shell pm uninstall --user 0 com.samsung.android.accessibility.talkback
adb shell pm uninstall --user 0 com.samsung.android.mcfds
adb shell pm uninstall --user 0 com.samsung.android.alive.service
adb shell pm uninstall --user 0 com.samsung.android.messaging
adb shell pm uninstall --user 0 com.samsung.android.mdx
adb shell pm uninstall --user 0 com.samsung.android.app.omcagent
adb shell pm uninstall --user 0 com.samsung.android.rubin.app
adb shell pm uninstall --user 0 com.samsung.android.smartsuggestions
adb shell pm uninstall --user 0 com.aura.oobe.samsung
adb shell pm uninstall --user 0 com.samsung.android.scloud
adb shell pm uninstall --user 0 com.google.android.adservices.api
adb shell pm uninstall --user 0 com.google.mainline.adservices
adb shell pm uninstall --user 0 com.samsung.android.knox.analytics.uploader
adb shell pm uninstall --user 0 com.samsung.android.scpm
adb shell pm uninstall --user 0 com.samsung.android.mapsagent
adb shell pm uninstall --user 0 com.samsung.android.app.settings.bixby 
# adb shell pm uninstall --user 0 com.sec.android.app.launcher # Do not remove this. The Recents button stops working.
