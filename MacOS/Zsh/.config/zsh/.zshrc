#----------------------------------------------------------------------------------#
#---------------                         Source                     ---------------#
#----------------------------------------------------------------------------------#
# Source global interactive shell alias and variables
[[ -r "$XDG_CONFIG_HOME/shell/alias.zsh" ]] && source "$XDG_CONFIG_HOME/shell/alias.zsh"
[[ -r "$XDG_CONFIG_HOME/shell/variables.zsh" ]] && source "$XDG_CONFIG_HOME/shell/variables.zsh"

# Put my scripts in the PATH for interactive shell
export PATH="${XDG_CONFIG_HOME}/shell/script:$PATH"

# Setup shell to enable the starship prompt
eval "$(starship init zsh)"

# Initialise zoxide
eval "$(zoxide init zsh)"

# Set up the yazi shell wrapper
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}


#----------------------------------------------------------------------------------#
#---------------                        General                     ---------------#
#----------------------------------------------------------------------------------#
# Setup command history
HISTSIZE=1000
SAVEHIST=1000

# Setup built-in autocompletion
zstyle :compinstall filename '/home/Zrabbit/.config/zsh/.zshrc'
autoload -Uz compinit
compinit
zstyle ':completion:*' use-cache on # Enabale completion caching for a faster experience
zstyle ':completion:*' menu select # Tab opens cmp menu
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} ma=0\;33 # Colorize the cmp menu

# The following lines are from me
bindkey -e # Enable normal mode
setopt nomatch # Prints an error if a pattern for filename generation has no matches
setopt append_history inc_append_history # Better history on exit, history appends rather than overwrites; history is appended as soon as cmds executed
setopt auto_menu menu_complete #autocmp first menu match
setopt auto_param_slash # When a dir is completed, add a / instead of a trailing space
setopt no_case_glob no_case_match # Make cmp case insensitive
setopt globdots # Don't need . in the filename to match dotfiles
setopt extended_glob # Match ~ # ^
setopt interactive_comments # Allow comments in shell 


#----------------------------------------------------------------------------------#
#---------------                   XDG Base Directory               ---------------#
#----------------------------------------------------------------------------------#
# Use XDG dirs for completion and history files
[ -d "$XDG_STATE_HOME"/zsh ] || mkdir -p "$XDG_STATE_HOME"/zsh
HISTFILE="$XDG_STATE_HOME"/zsh/history
[ -d "$XDG_CACHE_HOME"/zsh ] || mkdir -p "$XDG_CACHE_HOME"/zsh
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME"/zsh/zcompcache
compinit -d "$XDG_CACHE_HOME"/zsh/zcompdump-"$ZSH_VERSION"


#----------------------------------------------------------------------------------#
#---------------                         Plugin                     ---------------#
#----------------------------------------------------------------------------------#
# FZF intergration
# fzf shell integration (interactive only)
source <(fzf --zsh)

# Syntax highlighting
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
