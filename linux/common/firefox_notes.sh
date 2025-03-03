
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


