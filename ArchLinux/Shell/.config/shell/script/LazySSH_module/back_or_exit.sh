back_or_exit() {
    local input
    printf "\033[1;36m\nPress Enter to go back to the previous menu, any other keys exit the script...\033[0m"
    read -r input
    if [[ -z "$input" ]] && [[ "$1" == "main" ]]; then
        clear
        /home/Zrabbit/.config/shell/script/lazyssh
    elif [[ -z "$input" ]] && [[ "$1" == "previous" ]]; then
        clear
        /home/Zrabbit/.config/shell/script/LazySSH_module/github_related_menu
    else
        clear
        exit 0
    fi
}
