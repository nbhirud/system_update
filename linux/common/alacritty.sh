
# Alacritty config
# https://alacritty.org/config-alacritty.html

echo "************************ Install alacritty ************************"
sudo dnf install -y alacritty


echo "************************ Configure alacritty ************************"
mkdir -p $HOME/.config/alacritty/
cp linux/common/.alacritty.toml $HOME/.config/alacritty/alacritty.toml
