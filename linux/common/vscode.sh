#!/bin/sh

set -eux

sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc &&
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null


dnf check-update &&
sudo dnf install code # or code-insiders


# xdg-mime default code.desktop text/plain


# Extensions to install:
# Gemini Code Assist by Google
# Github Actions by Github
# Github Pull Reguests by Github
# AWS Toolkit by amazonwebservices
# Gitlab by Gitlab
# Gemini CLI Companion by Google
# Colab by Google

