# XDG Base Directory Spec
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_PICTURES_DIR="$HOME/Pictures"
export XDG_DOWNLOAD_DIR="$HOME/Downloads"
export XDG_DATA_DIRS="/usr/local/share:/usr/share:"
export XDG_CONFIG_DIRS="/etc/xdg/"

# Global variables
export EDITOR="nvim"
export VISUAL="nvim"
export SYSTEMD_EDITOR="nvim"
export BROWSER="zen-browser"
export BROWSER2="brave-origin-nightly"

# IME
export QT_IM_MODULE='fcitx'
export SDL_IM_MODULE='fcitx'
export XMODIFIERS='@im=fcitx'

#--------------- cargo ---------------#
export CARGO_HOME="$XDG_DATA_HOME"/cargo 

#---------------  npm  ---------------#
export NPM_CONFIG_USERCONFIG=$XDG_CONFIG_HOME/npm/npmrc

#---------------  gtk  ---------------#
export GTK2_RC_FILES="$XDG_CONFIG_HOME/gtk-2.0/gtkrc":"$XDG_CONFIG_HOME/gtk-2.0/gtkrc.mine"

#----------------  go  ---------------#
export GOPATH="$XDG_DATA_HOME"/go
export GOMODCACHE="$XDG_CACHE_HOME"/go/mod
export GOCACHE="$XDG_CACHE_HOME"/go/go-build

#-------------  starship  ------------#
export STARSHIP_CONFIG="$XDG_CONFIG_HOME"/zsh/starship.toml
export STARSHIP_CACHE="$XDG_CACHE_HOME"/starship

#----------------  GPG  ---------------#
export GNUPGHOME="$XDG_DATA_HOME"/gnupg/

#--------------  Arduino  -------------#
export ARDUINO_CONFIG_FILE="/home/Zrabbit/.config/arduino/arduino-cli.yaml"

#--------------  screen  --------------#
export SCREENRC="$XDG_CONFIG_HOME"/screen/screenrc
export SCREENDIR="${XDG_RUNTIME_DIR}/screen"

#------------ Java OpenJDK -------------#
export _JAVA_OPTIONS="-Djava.util.prefs.userRoot=${XDG_CONFIG_HOME:-$HOME/.config}/java"

#--------------  Zoxide  ---------------#
export _ZO_DATA_DIR="$XDG_DATA_HOME"/zoxide
export _ZO_ECHO=0
export _ZO_MAXAGE=10000

#----------------  WINE  -----------------#
export WINEPREFIX="$XDG_DATA_HOME"/wineprefixes/default
export WINEDLLOVERRIDES="winemenubuilder.exe=d"

#---------------- Docker -----------------#
export DOCKER_CONFIG="$XDG_CONFIG_HOME"/docker 
export MACHINE_STORAGE_PATH="$XDG_DATA_HOME"/docker-machine

#---------------- OpenCode ----------------#
export SUPERPOWERS_DISABLE_TELEMETRY=1
