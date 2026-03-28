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
'-h[Print help]' \
'--help[Print help]' \
'-V[Print version]' \
'--version[Print version]' \
':shell:(bash zsh fish elvish)' \
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
'completion:Print shell completion script to stdout' \
'doctor:Check paths, config, and basic environment' \
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
'completion:Print shell completion script to stdout' \
'doctor:Check paths, config, and basic environment' \
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
