
# Firefox, Librewolf and Mullvad browsers

######################################
## from Fedora 41
######################################


# Firefox
# First thing to do (STEP 1):
# https://github.com/arkenfox/user.js - The arkenfox user.js is a template which aims to provide as much privacy and enhanced security as possible, and to reduce tracking and fingerprinting as much as possible - while minimizing any loss of functionality and breakage (but it will happen).
# And then:
# Review all settings including labs
# and then:

#######################################

# Ublock Origin - Enable relevant filters
# https://github.com/mchangrh/yt-neuter - Add this filter to ublock origin

# replace hosts file - check ../security_os_level/


####################################### Privacy/youtube extensions - reference: https://www.youtube.com/watch?v=rteYHxcLCZk
# https://github.com/mchangrh/yt-neuter
#Return YouTube Dislike: https://returnyoutubedislike.com/
#SponsorBlock: https://sponsor.ajay.app/
#Dearrow (clickbait remover): https://dearrow.ajay.app/
#Unhook: https://unhook.app/
#uBlock Origin: https://ublockorigin.com/
#uBO troubleshooting:   / megathread
#uBO status: https://drhyperion451.github.io/does-...
#Hide YouTube Shorts: https://github.com/gijsdev/ublock-hid...
#NewPipe: https://newpipe.net/


echo "************************ Adding Librewolf repo ************************"
# LibreWolf - https://librewolf.net/installation/fedora/
# add the repo

# cd
# mkdir -p nb/temp
# cd nb/temp
# wget https://librewolf.net/installation/fedora/
# cat index.html | grep pkexec

# add the repo
curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo


echo "************************ Adding Mullvad repo ************************"
# https://mullvad.net/en/download/browser/linux
# Add the Mullvad repository server to dnf
# curl https://mullvad.net/en/download/browser/linux | grep addrepo
sudo dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo


sudo dnf install -y librewolf mullvad-browser


######################################
## from Fedora 40
######################################



### Firefox Tweaks:
# about:config
# layers.acceleration.force-enabled
# gfx.webrender.all

### 


# LibreWolf
# https://librewolf.net/installation/
# add the repo
curl -fsSL https://rpm.librewolf.net/librewolf-repo.repo | pkexec tee /etc/yum.repos.d/librewolf.repo
# install the package
sudo dnf install -y librewolf



curl -fsSL https://rpm.librewolf.net/librewolf-repo.repo | pkexec tee /etc/yum.repos.d/librewolf.repo
sudo dnf install -y librewolf



# another privacy browser:
# https://mullvad.net/en/download/browser/linux
# Add the Mullvad repository server to dnf
sudo dnf config-manager --add-repo https://repository.mullvad.net/rpm/stable/mullvad.repo
# Install the package
sudo dnf install mullvad-browser



######################################
## from Ubuntu
######################################


# remove snap firefox and install deb firefox
# Do this now because Firefox will be needed during the installing steps for general searching, version check, etc
sudo snap remove firefox
rm -r ~/snap/firefox

# https://support.mozilla.org/en-US/kb/install-firefox-linux
# Copying steps from above link here because I need to be able to run these steps after removing snap firefox
sudo install -d -m 0755 /etc/apt/keyrings # Create a directory to store APT repository keys if it doesn't exist
sudo apt install wget
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null # Import the Mozilla APT repository signing key
gpg -n -q --import --import-options import-show /etc/apt/keyrings/packages.mozilla.org.asc | awk '/pub/{getline; gsub(/^ +| +$/,""); if($0 == "35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3") print "\nThe key fingerprint matches ("$0").\n"; else print "\nVerification failed: the fingerprint ("$0") does not match the expected one.\n"}' # Check the fingerprint from above command
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee -a /etc/apt/sources.list.d/mozilla.list > /dev/null # add the Mozilla APT repository to your sources list
# Configure APT to prioritize packages from the Mozilla repository
echo '
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
' | sudo tee /etc/apt/preferences.d/mozilla

sudo apt update -y && sudo apt install -y firefox #  install the Firefox .deb package

# pin firefox again to Dash/Dock

# Login -> Let it stay open for a while as everything syncs and extensions install



##### Firefox:

# about:config
# layers.acceleration.force-enabled -> toggle to true
# gfx.webrender.all -> toggle to true

# UI Settings:
# General -> Startup -> enable "open previous windows and tabs"
# General -> Performance -> Enable "Use Hardware acceleration when available" and enable "Use recommended performance settings"
# General -> enable "Play DRM-controlled content" (find out whats this first)

# Privacy - 
    # Enhanced Tracking Protection = Strict
    # Websitr Privacy Preferences - enable both options (sell/share data and do not track)

# Ublock Origin - Enable relevant filters
# https://github.com/mchangrh/yt-neuter - Add this filter to ublock origin
# https://github.com/StevenBlack/hosts - modify hosts file - sudo nano /etc/hosts
# https://github.com/arkenfox/user.js - The arkenfox user.js is a template which aims to provide as much privacy and enhanced security as possible, and to reduce tracking and fingerprinting as much as possible - while minimizing any loss of functionality and breakage (but it will happen).




##### Firefox:
# Login

# Privacy

# General -> Language and appearance -> Choose dark/light to Automatic 



##########
# LibreWolf
# https://librewolf.net/installation/
sudo apt update && sudo apt install -y wget gnupg lsb-release apt-transport-https ca-certificates
distro=$(if echo " una bookworm vanessa focal jammy bullseye vera uma " | grep -q " $(lsb_release -sc) "; then lsb_release -sc; else echo focal; fi)
wget -O- https://deb.librewolf.net/keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/librewolf.gpg

sudo tee /etc/apt/sources.list.d/librewolf.sources << EOF > /dev/null
Types: deb
URIs: https://deb.librewolf.net
Suites: $distro
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/librewolf.gpg
EOF

sudo apt update
sudo apt install librewolf -y


###########

# another privacy browser:
# https://mullvad.net/en/download/browser/linux

# Download the Mullvad signing key
sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc

# Add the Mullvad repository server to apt
echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$( dpkg --print-architecture )] https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/mullvad.list

# Install the package
sudo apt update
sudo apt install mullvad-browser


######################################
## from Arch
######################################

# https://wiki.archlinux.org/title/Firefox#Hardware_video_acceleration


######################################
## from Alpine
######################################

# https://support.mozilla.org/en-US/kb/install-firefox-linux?as=u&utm_source=inproduct#w_security-features-warning


######################################
## from here
######################################

https://askubuntu.com/a/32649



This setting should go into your Firefox profile prefs.js file, which should be located in ~/.mozilla/firefox/*.default/.

The file format is JavaScript, so in theory it could be mangled to the point of needing a JS parser to modify it, but Firefox is usually nice and prints each setting on its own line in alphabetical order. To add a setting like this you could simply

echo 'user_pref("toolkit.networkmanager.disable", true);' >> ~/.mozilla/firefox/**replace**.default/prefs.js

If this setting is already in the file, I'm not sure whether Firefox will register the last or first instance. Just give it a try. If it's not consistent, you could do this:

if grep 'toolkit.networkmanager.disable' ~/.mozilla/firefox/*.default/prefs.js
then
    sed -i -e 's/^user_pref("toolkit.networkmanager.disable", \(true\|false\));$/user_pref("toolkit.networkmanager.disable", true);/' ~/.mozilla/firefox/*.default/prefs.js
else
    echo 'user_pref("toolkit.networkmanager.disable", true);' >> ~/.mozilla/firefox/*.default/prefs.js
fi

After modifying the configuration you'll need to restart Firefox to apply the change.


##################################

Here is a possible shell script. You have to cd to your profile directory before using it (where the user.js is). Say the script is called ff_set you could call it like:

ff_set browser.search.defaulturl '"https://duckduckgo.com/"'

Here is the code:

#!/bin/bash

sed -i 's/user_pref("'$1'",.*);/user_pref("'$1'",'$2');/' user.js
grep -q $1 user.js || echo "user_pref(\"$1\",$2);" >> user.js

#################################3


Here Is An Example Script For Your Request:

#!/bin/bash
 cd ~/.mozilla/firefox/
 sed -i 's/user_pref("'$1'",.*);/user_pref("'$1'",'$2');/' user.js
 grep -q $1 user.js || echo "user_pref(\"$1\",$2);" >> user.js

You need to edit the mozilla path to your profile dir if the path on first line is wrong.
Find Alot More Info In URL Below: https://developer.mozilla.org/en-US/docs/Mozilla/Command_Line_Options

#################################

http://kb.mozillazine.org/Category:Preferences

https://developer.mozilla.org/En/A_Brief_Guide_to_Mozilla_Preferences

http://kb.mozillazine.org/About:config_entries


https://developer.mozilla.org/En/A_Brief_Guide_to_Mozilla_Preferences



http://sourceforge.net/projects/firefoxadm/

#######################################

cd /D "%APPDATA%\Mozilla\Firefox\Profiles\*.default"

set ffile=%cd%

echo user_pref("browser.startup.homepage", "http://superuser.com");>>"%ffile%\prefs.js"
echo user_pref("browser.search.defaultenginename", "Google");>>"%ffile%\prefs.js"
echo user_pref("app.update.auto", false);>>"%ffile%\prefs.js"
set ffile=

cd %windir%


########################################



:: The thread is a litte old, but I want to share my solution anyways. Hope this helps someone. We had a similar problem and wanted to add the certificates from windows store into firefox. So I created a script to do so. Anyways, you can change it to your needs: Just add or remove the lines at :: create cfg_file_name.cfg[...] and insert what you need e.g.  echo pref("browser.startup.homepage", "http://superuser.com"^); for start homepage and so on. Remember to set the ^ before the last ), otherwise it will not work!

:: Since version 49 you can do it like that: 


@echo off
setlocal enabledelayedexpansion
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: MAIN INFORMATION
:: Title: Change about:config entries in Mozilla Firefox
:: Author: I-GaLaXy-I
:: Version: 1.1
:: Last Modified: 10.01.2018
:: Last Modified by: I-GaLaXy-I
::------------------------------------------------------------------------------
:: This script will add two files, which will change about:config parameters of
:: Mozilla Firefox. You can change the name of these two files and remove or add
:: parameters according to your needs. Renaming the files could be essential, if
:: a user creates own files and you don't want to overwrite them.
:: 
:: If the two files already exist and the script is run, the complete content
:: of both files will be overwritten!
::
:: Note: You may have to run it with administrative privileges!
::
:: More information: https://developer.mozilla.org/en-US/Firefox/Enterprise_deployment
:: http://kb.mozillazine.org/Locking_preferences
::------------------------------------------------------------------------------
:: Subtitle: Import CAs from Windows certificate store
:: More information: https://serverfault.com/questions/722563/how-to-make-firefox-trust-system-ca-certificates
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:: Set the name of the .cfg file
set cfg_file_name=add_win_certstore_cas

:: Set the name of the .js file
set js_file_name=add_win_certstore_cas

:: Registry keys to check for the installation path of Mozilla Firefox
set regkey1="HKEY_LOCAL_MACHINE\SOFTWARE\MICROSOFT\Windows\CurrentVersion\App Paths\firefox.exe" /v "Path"
set regkey2="HKEY_LOCAL_MACHINE\SOFTWARE\Clients\StartMenuInternet\FIREFOX.EXE\shell\open\command" /ve

:: Get installation path of Mozilla Firefox (if not found exit script):
reg query %regkey1%
if %errorlevel%==0 (
    :: First key found, getting path
    for /f "tokens=2* delims=    " %%a in ('reg query %regkey1%') do set path_firefox=%%b
) else (
    :: If first key not found, try another one:
    reg query %regkey2%
    if !errorlevel!==0 (
        for /f "tokens=2* delims=    " %%a in ('reg query %regkey2%') do set path_firefox=%%b
        set path_firefox=!path_firefox:\firefox.exe=!
        for /f "useback tokens=*" %%a in ('!path_firefox!') do set path_firefox=%%~a
) else (
    :: No key found, exit script
    exit
))

:: Create cfg_file_name.cfg if it doesn't exist and input the following lines.
:: Caution! If cfg_file_name.cfg already exists, all lines will be overwritten!
:: Add more lines as needed with the following syntax: 
::echo pref("<name_of_config_entry>", <value>^);
(
    echo //Firefox Settings rolled out via KACE from Systec
    echo //Do not manually edit this file because it will be overwritten!
    echo //Import CAs that have been added to the Windows certificate store by an user or administrator.
    echo pref("security.enterprise_roots.enabled", true^);
) > "%path_firefox%\%cfg_file_name%.cfg"

:: Create js_file_name.js if it doesn't exist and input the following lines.
:: Caution! If js_file_name.js already exists, all lines will be overwritten!
(
    echo /* Firefox Settings rolled out via KACE from Systec
    echo Do not manually edit this file because it will be overwritten! */
    echo pref("general.config.obscure_value", 0^);
    echo pref("general.config.filename", "%cfg_file_name%.cfg"^);
) > "%path_firefox%\defaults\pref\%js_file_name%.js"

:: Files created, exit
exit


####################################################

https://www.local-guru.net/blog/2007/11/03/automatic-proxy-configuration-in-firefox

In an erlier article i describe how to switch between the network environments i am using, but there was one programm i could not convince to let me change the proxy settings via apple script - firefox.

i still needet to switch the firefox settings per hand - something i didnt like at all.

one day the little "fetch proxy settings for url" dialog part from the firefox proxysettigns made me courious and i found out, that firefox expects a javascript file on this url, which tells firefox what proxy to use.

function FindProxyForURL(url, host) {
    if ( dnsResolve( host ) == "127.0.0.1" ) {
        return "DIRECT";
    } else {
        return "PROXY proxyhost:8080";
    }
}

this script can use some predefined functions like "isInNet" or "dnsResolve" to determine which network Im in and use the appropriate proxy. the file doesnt even have to live on a http server, a file:// url is sufficient.

e voila - no more manual proxy switching


#################################################

https://linuxconfig.org/firefox-and-the-linux-command-line


#################################################

/home/nbhirud/.librewolf/mz5p9hr1.default-default/prefs.js

#################################################

https://en.wikipedia.org/wiki/Proxy_auto-config



I can't find any way to reload the prefs.js file (that's where firefox stores its settings) after changing it from the command line. That's a shame 'cause that would have been the simplest way of doing it.

However, for the specific setting you want to change, you could simply set up a proxy.pac file which checks if your IP is in a particular subnet and only sets up a proxy if it is:

if (isInNet(myIpAddress(), "192.168.1.0", "255.252.0.0")) { 
     proxy = "PROXY 123.456.789.100:12345";
}
else{
     proxy = "DIRECT";
}
return proxy;

Obviously, you should use your actual proxy's URL and port. You'll also need to modify it so it runs the correct tests (IP range etc) for your setup.

Now, open the proxy setting tab, select the "Automatic proxy configuration URL" and point it to: file:////path/to/proxy.pac. Restart firefox and you should now have your proxy set automatically depending on your IP address. 

http://findproxyforurl.com/pac-functions/


##########################################################3

https://web.mit.edu/~firefox/www/maintainers/autoconfig.html


############################################################
https://github.com/yokoffing/Betterfox

https://github.com/yokoffing/NextDNS-Config


###########################################################
https://brainfucksec.github.io/firefox-hardening-guide-2024


#########################################################

https://wiki.archlinux.org/title/Firefox
https://wiki.archlinux.org/title/Firefox/Tweaks
https://wiki.archlinux.org/title/Firefox#Configuration
https://wiki.archlinux.org/title/Browser_extensions
https://wiki.archlinux.org/title/Language_checking#Spell_checkers
https://wiki.archlinux.org/title/Domain_name_resolution#Application-level_DNS
https://blog.cloudflare.com/oblivious-dns/
https://wiki.archlinux.org/title/Systemd-nspawn#Run_Firefox
https://www.debian.org/doc/manuals/debian-handbook/sect.hostname-name-service.en.html#sect.name-resolution
https://wiki.archlinux.org/title/Firefox/Privacy
https://wiki.archlinux.org/title/Talk:Firefox/Privacy
https://github.com/curl/curl/wiki/DNS-over-HTTPS#publicly-available-servers
https://searx.space/#



