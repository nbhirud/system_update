
# echo $XDG_CURRENT_DESKTOP
# echo $DESKTOP_SESSION
# echo $GDMSESSION

# TODO - Make it foolproof. Currently only tested with Gnome

if [ "$XDG_CURRENT_DESKTOP" = "" ]
then
  desktop=$(echo "$XDG_DATA_DIRS" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/')
else
  desktop=$XDG_CURRENT_DESKTOP
fi

desktop=${desktop,,}  # convert to lower case
echo "$desktop"
