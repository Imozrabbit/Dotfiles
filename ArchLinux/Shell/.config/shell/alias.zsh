# Colorize
alias ls='ls -a -A --color=auto'
alias grep='grep --color=auto'

# General Apps
alias hypr='start-hyprland'
alias n='nvim'
alias ai='opencode'
alias weather='curl wttr.in/strasbourg'

# File management and navigation
alias cd..="cd .."
alias .='cd ..'
alias ..='cd ../..'
alias ...='cd ../../..'
alias open='thunar .'
alias mkdir='mkdir -p -v'
alias cat='bat --color always'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias root='cd /'
alias dotfile='cd /home/Zrabbit/Documents/Dotfiles/ArchLinux/'

# Compression and Extraction
alias untar='tar -xvf' # Extract verbally a .tar file
alias untargz='tar -zvxf' # Extract verbally a .tar.gz file

# Pacman
alias update_sys='sudo pacman -Syu'
alias update_all='yay -Syu && flatpak update --user'
alias orphan='yay -Qdtq'

# Global
alias -g PATH='echo $PATH | tr ":" "\n"' # Show $PATH line by line
alias -g GI='| rg -i'
alias -g WCL='| wc -l'
alias -g L='| less'
