# Colorize
alias ls='ls -A --color=auto'
alias grep='grep --color=auto'

# General Apps
alias n='nvim'
alias ai='opencode'

# File management and navigation
alias cd..="cd .."
alias .='cd ..'
alias ..='cd ../..'
alias ...='cd ../../..'
alias mkdir='mkdir -p -v'
alias cat='bat --color always'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias root='cd /'
alias dotfile='cd /Users/zrabbit/Documents/Dotfiles/MacOS/'

# Compression and Extraction
alias untar='tar -xvf' # Extract verbally a .tar file
alias untargz='tar -zvxf' # Extract verbally a .tar.gz file

# Homebrew
alias update="brew update && brew upgrade"
alias brew_uninstall_cask='brew uninstall --cask --zap'

# Global
alias -g PATH='echo $PATH | tr ":" "\n"' # Show $PATH line by line
alias -g GI='| rg -i'
alias -g WCL='| wc -l'
alias -g L='| less'
