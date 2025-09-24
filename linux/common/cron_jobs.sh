# check if the OS is fedora. If not, then exit.

# Create a directory ~/nb/nbLogs and write output of each of these cron jobs to this dir in a timestamped filename format.
# Also create errors_<datestamp>.log file in this dir to see daily errors quickly. Modify cron jobs to write to normal logs (aith all info) and errors file  with only errors and warnings.

# run git pull (with git stash and git stash pop when it makes sense) in some directories like 
# 1. subdirectories of ~/nb/CodeProjects/
# 2. /home/nbhirud/.oh-my-zsh
# 3. subdirectories of ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/
# 4. Add to this list as you figure out more


# clamav - have done something for updates to this. Check it


# clamav - scan once a week


# once a week? - sh $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/proton_ag_stuff.sh


# nbpdate - on startup, shutdown and every hour maybe


# nbclean - on shutdown


# hosts - on startup and shutdown - don't just blindly replace. Figure out checking if there is really an update available


# nerd fonts - update when updates are available (on startup and) shutdown


# clean up old kernels - once a week


# update kodi related stuff if kodi is installed and if updates available


