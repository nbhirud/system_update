#######################################################
# Deploy Extensibility Plugins / Scripts - yt-dlp integration
#######################################################

# # 2. yt-dlp integration (Replace youtube-dl entirely)

# # Following is alternative way to install the latest version of yt-dlp. But we are using fedora package instead (dnf install)
# # curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
# #   -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp

# # The dnf package:
# # >> which yt-dlp
# # /usr/bin/yt-dlp  

# # Create the youtube-dl wrapper script (MPV expects 'youtube-dl' sometimes)
# cat > "$SCRIPT_DIR/youtube-dl.lua" <<EOF
# #!/bin/bash
# # exec /usr/local/bin/yt-dlp "\$@"
# exec /usr/bin/yt-dlp "\$@"
# EOF
# chmod +x "$SCRIPT_DIR/youtube-dl.lua"
# # mv youtube-dl youtube-dl.lua # Actually, just ensure the binary is in PATH