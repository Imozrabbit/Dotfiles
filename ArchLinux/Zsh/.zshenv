# Bootstrap: load the real zsh config files like zshrc and zshenv from XDG config
export ZDOTDIR="$HOME/.config/zsh"
[[ -r "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
