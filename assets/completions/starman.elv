
use builtin;
use str;

set edit:completion:arg-completer[starman] = {|@words|
    fn spaces {|n|
        builtin:repeat $n ' ' | str:join ''
    }
    fn cand {|text desc|
        edit:complex-candidate $text &display=$text' '(spaces (- 14 (wcswidth $text)))$desc
    }
    var command = 'starman'
    for word $words[1..-1] {
        if (str:has-prefix $word '-') {
            break
        }
        set command = $command';'$word
    }
    var completions = [
        &'starman'= {
            cand --no-color 'Disable ANSI colors (also respects NO_COLOR)'
            cand -h 'Print help (see more with ''--help'')'
            cand --help 'Print help (see more with ''--help'')'
            cand -V 'Print version'
            cand --version 'Print version'
            cand tui 'Interactive full-screen TUI (requires a TTY on stdout)'
            cand version 'Print version and exit'
            cand completion 'Print shell completion script to stdout (redirect or eval — see long help)'
            cand doctor 'Check paths, config, and basic environment'
            cand create-user 'Create a UNIX user with shell snippets, optional group & Linuxbrew (requires root)'
            cand help 'Print this message or the help of the given subcommand(s)'
        }
        &'starman;tui'= {
            cand --no-color 'Disable ANSI colors (also respects NO_COLOR)'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'starman;version'= {
            cand --no-color 'Disable ANSI colors (also respects NO_COLOR)'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'starman;completion'= {
            cand --no-color 'Disable ANSI colors (also respects NO_COLOR)'
            cand -h 'Print help (see more with ''--help'')'
            cand --help 'Print help (see more with ''--help'')'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'starman;doctor'= {
            cand --no-color 'Disable ANSI colors (also respects NO_COLOR)'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'starman;create-user'= {
            cand -g '协作 UNIX 组（默认见配置 `default_user_group`，一般为 lab）'
            cand --group '协作 UNIX 组（默认见配置 `default_user_group`，一般为 lab）'
            cand --shell '登录 shell（默认见配置 `default_shell`）'
            cand --home-quota '家目录所在文件系统上的用户磁盘配额（软/硬相同，块配额）；如 `200G`、`500M`。默认 200G，见配置 `default_home_quota`'
            cand --no-brew '不初始化 Linuxbrew（跳过 `brew bundle`）'
            cand --no-quota '不设置磁盘配额（忽略默认 200G）'
            cand --no-color 'Disable ANSI colors (also respects NO_COLOR)'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'starman;help'= {
            cand tui 'Interactive full-screen TUI (requires a TTY on stdout)'
            cand version 'Print version and exit'
            cand completion 'Print shell completion script to stdout (redirect or eval — see long help)'
            cand doctor 'Check paths, config, and basic environment'
            cand create-user 'Create a UNIX user with shell snippets, optional group & Linuxbrew (requires root)'
            cand help 'Print this message or the help of the given subcommand(s)'
        }
        &'starman;help;tui'= {
        }
        &'starman;help;version'= {
        }
        &'starman;help;completion'= {
        }
        &'starman;help;doctor'= {
        }
        &'starman;help;create-user'= {
        }
        &'starman;help;help'= {
        }
    ]
    $completions[$command]
}
