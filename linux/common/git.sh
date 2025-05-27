# Script to setup git on a new machine or new installation of OS
echo "************************ Configure git ************************"

# https://git-scm.com/book/en/v2/Customizing-Git-Git-Configuration
git config --global user.name "Nikhil Bhirud"

# TODO replace with correct email
# git config --global user.email "<place xyz@users.noreply.github.com from github here>"

# https://code.visualstudio.com/docs/sourcecontrol/overview#_vs-code-as-git-difftool-and-mergetool
git config --global core.editor "codium --wait" # # https://git-scm.com/book/en/v2/Appendix-C:-Git-Commands-Setup-and-Config
git config --global merge.tool codium # codium might not be supported. vscode is supported
# check supported merge tools:
# git mergetool --tool-help

git config --global core.autocrlf input # # Configure Git to ensure line endings in files you checkout are correct for Linux

git config --global init.defaultBranch main


git config --global  help.autocorrect 1


git config --global color.ui true # default is true

# The above sets all the below. Allowed values = true, false, or always:
# color.branch
# color.diff
# color.interactive
# color.status

############################
# git config --global commit.template ~/.gitmessage.txt
# # TODO create the temopate file ~/.gitmessage.txt as follows (uncomment):
# # Subject line (try to keep under 50 characters)

# # Multi-line description of commit,
# # feel free to be detailed.

# # [Ticket: X]
############################

# git config --global core.excludesfile ~/.gitignore_global
# # create file ~/.gitignore_global with following content syntax (uncomment):
# # *~
# # .*.swp
# # .DS_Store

############################

# git hooks
# https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks
############################

# # garbage collect
# # https://git-scm.com/book/en/v2/Git-Internals-Maintenance-and-Data-Recovery
# git gc 
# # git gc --auto

############################
# # git config --list

# # https://docs.github.com/en/get-started/git-basics/set-up-git
# gh auth login

# # also see:
# # https://www.jetbrains.com/help/idea/using-git-integration.html
# # https://git-scm.com/book/en/v2/Appendix-A:-Git-in-Other-Environments-Git-in-IntelliJ-/-PyCharm-/-WebStorm-/-PhpStorm-/-RubyMine
# # https://git-scm.com/book/en/v2/Appendix-A:-Git-in-Other-Environments-Git-in-Zsh # if not using omz

# # 
