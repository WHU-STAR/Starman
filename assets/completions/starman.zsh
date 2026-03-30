#compdef starman

autoload -U is-at-least

_starman() {
    typeset -A opt_args
    typeset -a _arguments_options
    local ret=1

    if is-at-least 5.2; then
        _arguments_options=(-s -S -C)
    else
        _arguments_options=(-s -C)
    fi

    local context curcontext="$curcontext" state line
    _arguments "${_arguments_options[@]}" \
'--no-color[Disable ANSI colors (also respects NO_COLOR)]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'-V[Print version]' \
'--version[Print version]' \
":: :_starman_commands" \
"*::: :->starman" \
&& ret=0
    case $state in
    (starman)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:starman-command-$line[1]:"
        case $line[1] in
            (tui)
_arguments "${_arguments_options[@]}" \
'--no-color[Disable ANSI colors (also respects NO_COLOR)]' \
'-h[Print help]' \
'--help[Print help]' \
'-V[Print version]' \
'--version[Print version]' \
&& ret=0
;;
(version)
_arguments "${_arguments_options[@]}" \
'--no-color[Disable ANSI colors (also respects NO_COLOR)]' \
'-h[Print help]' \
'--help[Print help]' \
'-V[Print version]' \
'--version[Print version]' \
&& ret=0
;;
(completion)
_arguments "${_arguments_options[@]}" \
'--no-color[Disable ANSI colors (also respects NO_COLOR)]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'-V[Print version]' \
'--version[Print version]' \
':shell -- Target shell:(bash zsh fish elvish power-shell)' \
&& ret=0
;;
(doctor)
_arguments "${_arguments_options[@]}" \
'--no-color[Disable ANSI colors (also respects NO_COLOR)]' \
'-h[Print help]' \
'--help[Print help]' \
'-V[Print version]' \
'--version[Print version]' \
&& ret=0
;;
(create-user)
_arguments "${_arguments_options[@]}" \
'-g+[协作 UNIX 组（默认见配置 \`default_user_group\`，一般为 lab）]:GROUP: ' \
'--group=[协作 UNIX 组（默认见配置 \`default_user_group\`，一般为 lab）]:GROUP: ' \
'--shell=[登录 shell（默认见配置 \`default_shell\`）]:SHELL: ' \
'--home-quota=[家目录所在文件系统上的用户磁盘配额（软/硬相同，块配额）；如 \`200G\`、\`500M\`。默认 200G，见配置 \`default_home_quota\`]:SIZE: ' \
'--no-brew[不初始化 Linuxbrew（跳过 \`brew bundle\`）]' \
'--no-quota[不设置磁盘配额（忽略默认 200G）]' \
'--no-color[Disable ANSI colors (also respects NO_COLOR)]' \
'-h[Print help]' \
'--help[Print help]' \
'-V[Print version]' \
'--version[Print version]' \
':username -- 新登录名（小写字母、数字、_、-）:' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
":: :_starman__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:starman-help-command-$line[1]:"
        case $line[1] in
            (tui)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(version)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(completion)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(doctor)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(create-user)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
}

(( $+functions[_starman_commands] )) ||
_starman_commands() {
    local commands; commands=(
'tui:Interactive full-screen TUI (requires a TTY on stdout)' \
'version:Print version and exit' \
'completion:Print shell completion script to stdout (redirect or eval — see long help)' \
'completions:Print shell completion script to stdout (redirect or eval — see long help)' \
'doctor:Check paths, config, and basic environment' \
'create-user:Create a UNIX user with shell snippets, optional group & Linuxbrew (requires root)' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'starman commands' commands "$@"
}
(( $+functions[_starman__completion_commands] )) ||
_starman__completion_commands() {
    local commands; commands=()
    _describe -t commands 'starman completion commands' commands "$@"
}
(( $+functions[_starman__help__completion_commands] )) ||
_starman__help__completion_commands() {
    local commands; commands=()
    _describe -t commands 'starman help completion commands' commands "$@"
}
(( $+functions[_starman__create-user_commands] )) ||
_starman__create-user_commands() {
    local commands; commands=()
    _describe -t commands 'starman create-user commands' commands "$@"
}
(( $+functions[_starman__help__create-user_commands] )) ||
_starman__help__create-user_commands() {
    local commands; commands=()
    _describe -t commands 'starman help create-user commands' commands "$@"
}
(( $+functions[_starman__doctor_commands] )) ||
_starman__doctor_commands() {
    local commands; commands=()
    _describe -t commands 'starman doctor commands' commands "$@"
}
(( $+functions[_starman__help__doctor_commands] )) ||
_starman__help__doctor_commands() {
    local commands; commands=()
    _describe -t commands 'starman help doctor commands' commands "$@"
}
(( $+functions[_starman__help_commands] )) ||
_starman__help_commands() {
    local commands; commands=(
'tui:Interactive full-screen TUI (requires a TTY on stdout)' \
'version:Print version and exit' \
'completion:Print shell completion script to stdout (redirect or eval — see long help)' \
'doctor:Check paths, config, and basic environment' \
'create-user:Create a UNIX user with shell snippets, optional group & Linuxbrew (requires root)' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'starman help commands' commands "$@"
}
(( $+functions[_starman__help__help_commands] )) ||
_starman__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'starman help help commands' commands "$@"
}
(( $+functions[_starman__help__tui_commands] )) ||
_starman__help__tui_commands() {
    local commands; commands=()
    _describe -t commands 'starman help tui commands' commands "$@"
}
(( $+functions[_starman__tui_commands] )) ||
_starman__tui_commands() {
    local commands; commands=()
    _describe -t commands 'starman tui commands' commands "$@"
}
(( $+functions[_starman__help__version_commands] )) ||
_starman__help__version_commands() {
    local commands; commands=()
    _describe -t commands 'starman help version commands' commands "$@"
}
(( $+functions[_starman__version_commands] )) ||
_starman__version_commands() {
    local commands; commands=()
    _describe -t commands 'starman version commands' commands "$@"
}

if [ "$funcstack[1]" = "_starman" ]; then
    _starman "$@"
else
    compdef _starman starman
fi
