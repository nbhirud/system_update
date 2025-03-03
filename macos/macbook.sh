
#keeping macbook up to date:
# Not sure if there is a better format for mac than *.sh


# Check if an OS update is there in the list. If yes, excluse it because it will restart the macbook in the 
# middle of the updates, and the updates queued up after the OS update won't happen. Keep OS update for the end

softwareupdate --list 

# Use exclude option below if above list has OS update
softwareupdate --all --install --force

# update/upgrade all the brew packages
brew update && brew upgrade

# do not install python using brew
