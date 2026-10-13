#!/bin/bash

set -eux


######################################
# flyline for bash
######################################




######################################
# flyline for bash
######################################

# https://github.com/HalFrgrd/flyline
# https://itsfoss.com/flyline/?ref=foss-weekly-newsletter#install-flyline

# source <(curl -sSfL https://github.com/HalFrgrd/flyline/releases/latest/download/install.sh)
curl -sSfL https://github.com/HalFrgrd/flyline/releases/latest/download/install.sh | sh

# enable flyline 2>/dev/null || enable -f "~/.local/lib/libflyline.so" flyline
enable flyline 2>/dev/null || enable -f "/home/nbhirud/.local/lib/libflyline.so" flyline

# flyline run-tutorial

# To uninstall flyline:
# enable -d flyline
# rm -f ~/.local/lib/libflyline.so*
# Finally, open your ~/.bashrc and remove the line that loads Flyline. It should look similar to this:
# enable flyline 2>/dev/null || enable -f "~/.local/lib/libflyline.so" flyline

