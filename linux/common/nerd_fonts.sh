


dconf write /org/gnome/desktop/interface/font-name "'Ubuntu Nerd Font 11'"
dconf write /org/gnome/desktop/interface/document-font-name "'Ubuntu Nerd Font 11'"
dconf write /org/gnome/desktop/wm/preferences/titlebar-font "'Ubuntu Nerd Font Bold 11'"
dconf write /org/gnome/desktop/interface/monospace-font-name "'JetBrainsMono Nerd Font 10'"

# You can also use the gsettings commandline tool instead of the Dconf Editor GUI tool

# Example font search for setting as default as monospace font for firefox
# fc-list | grep Nerd | grep -v Propo | grep -v Bold | grep -v Condense | grep -v Extra | grep -v Light | grep -v Italic | grep -v Thin | grep -v Medium | grep -v Black | grep "Noto" 