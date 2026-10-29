-- AUR endpoints
yay.opt.aururl = "https://aur.archlinux.org"
yay.opt.aurrpcurl = ""
yay.opt.build_dir = os.getenv("HOME") .. "/.cache/yay"
yay.opt.editor = os.getenv("EDITOR") or os.getenv("VISUAL") or "vi"
yay.opt.editor_flags = ""
yay.opt.makepkg_bin = "makepkg"
yay.opt.makepkg_conf = ""
yay.opt.pacman_bin = "pacman"
yay.opt.pacman_conf = "/etc/pacman.conf"
yay.opt.redownload = "no"
yay.opt.git_bin = "git"
yay.opt.git_flags = ""
yay.opt.gpg_bin = "gpg"
yay.opt.gpg_flags = ""
yay.opt.sudo_bin = "sudo"
yay.opt.sudo_flags = ""
yay.opt.mflags = ""

-- Search behavior
yay.opt.sort_by = "popularity"
yay.opt.search_by = "name-desc"
yay.opt.bottom_up = true
yay.opt.single_line_results = false
yay.opt.separate_sources = true

-- Download and build behavior
yay.opt.redownload = "no" -- no | yes | all
yay.opt.rebuild = "no" -- no | yes | tree | all
yay.opt.remove_make = "yes" -- no | yes | ask | askyes
yay.opt.keep_src = false
yay.opt.clean_after = true
yay.opt.batch_install = false
yay.opt.max_concurrent_downloads = 1

-- AUR queries and dependencies
yay.opt.request_split_n = 150
yay.opt.completion_refresh_time = 7
yay.opt.provides = true
yay.opt.pgp_fetch = true
yay.opt.rpc = true

-- Update behavior
yay.opt.devel = false
yay.opt.combined_upgrade = true
yay.opt.sudo_loop = false
yay.opt.use_ask = false
yay.opt.double_confirm = true

-- Interactive menus
yay.opt.clean_menu = true
yay.opt.diff_menu = true
yay.opt.edit_menu = false

-- Preset menu answers
-- Empty string preserves interactive prompting.
yay.opt.answer_clean = "None"
yay.opt.answer_diff = "None"
yay.opt.answer_edit = ""

-- Diagnostics
yay.opt.debug = false
