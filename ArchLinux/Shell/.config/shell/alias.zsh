# Colorize
alias ls='ls -a -A --color=auto'
alias grep='grep --color=auto'

# General Apps
alias hypr='start-hyprland'
alias n='nvim'
alias ai='opencode'
alias weather='curl wttr.in/strasbourg'

# Navigation
alias data='z /home/Zrabbit/.local/share'
alias state='z /home/Zrabbit/.local/state'
alias config='z /home/Zrabbit/.config'
alias cache='z /home/Zrabbit/.cache'
alias dotfile='z /home/Zrabbit/Documents/Dotfiles'
alias root='z /'
alias z..="z .."
alias ..='z ..'
alias ....='z ../..'
alias ......='z ../../..'

# File management
alias open='thunar .'
alias mkdir='mkdir -p -v'
alias cat='bat --color always'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'

# Compression and Extraction
alias untar='tar -xvf' # Extract verbally a .tar file
alias untargz='tar -zvxf' # Extract verbally a .gz file

# Pacman
alias updatesys='sudo pacman -Syu'
alias updateall='yay -Syu && flatpak update --user'
alias orphan='yay -Qdtq'

# Global
alias -g PATH='echo $PATH | tr ":" "\n"' # Show $PATH line by line
alias -g GI='| rg -i'
alias -g WCL='| wc -l'
alias -g L='| less'

# Wine Prefix
alias winecfg-ltspice='WINEPREFIX="$HOME/.local/share/wineprefixes/LTSpice" winecfg'

# NetworkManager TUI
alias nmtui="NEWT_COLORS='root=white,black;window=white,black;border=white,black;title=white,black;textbox=white,black;label=white,black;listbox=white,black;actlistbox=black,white;entry=white,black;button=black,white;actbutton=black,lightgray' /usr/bin/nmtui"
