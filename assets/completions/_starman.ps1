
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Register-ArgumentCompleter -Native -CommandName 'starman' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commandElements = $commandAst.CommandElements
    $command = @(
        'starman'
        for ($i = 1; $i -lt $commandElements.Count; $i++) {
            $element = $commandElements[$i]
            if ($element -isnot [StringConstantExpressionAst] -or
                $element.StringConstantType -ne [StringConstantType]::BareWord -or
                $element.Value.StartsWith('-') -or
                $element.Value -eq $wordToComplete) {
                break
        }
        $element.Value
    }) -join ';'

    $completions = @(switch ($command) {
        'starman' {
            [CompletionResult]::new('--no-color', 'no-color', [CompletionResultType]::ParameterName, 'Disable ANSI colors (also respects NO_COLOR)')
            [CompletionResult]::new('-h', 'h', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
            [CompletionResult]::new('--help', 'help', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
            [CompletionResult]::new('-V', 'V ', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('--version', 'version', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('tui', 'tui', [CompletionResultType]::ParameterValue, 'Interactive full-screen TUI (requires a TTY on stdout)')
            [CompletionResult]::new('version', 'version', [CompletionResultType]::ParameterValue, 'Print version and exit')
            [CompletionResult]::new('completion', 'completion', [CompletionResultType]::ParameterValue, 'Print shell completion script to stdout (redirect or eval — see long help)')
            [CompletionResult]::new('doctor', 'doctor', [CompletionResultType]::ParameterValue, 'Check paths, config, and basic environment')
            [CompletionResult]::new('create-user', 'create-user', [CompletionResultType]::ParameterValue, 'Create a UNIX user with shell snippets, optional group & Linuxbrew (requires root)')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'starman;tui' {
            [CompletionResult]::new('--no-color', 'no-color', [CompletionResultType]::ParameterName, 'Disable ANSI colors (also respects NO_COLOR)')
            [CompletionResult]::new('-h', 'h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', 'help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('-V', 'V ', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('--version', 'version', [CompletionResultType]::ParameterName, 'Print version')
            break
        }
        'starman;version' {
            [CompletionResult]::new('--no-color', 'no-color', [CompletionResultType]::ParameterName, 'Disable ANSI colors (also respects NO_COLOR)')
            [CompletionResult]::new('-h', 'h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', 'help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('-V', 'V ', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('--version', 'version', [CompletionResultType]::ParameterName, 'Print version')
            break
        }
        'starman;completion' {
            [CompletionResult]::new('--no-color', 'no-color', [CompletionResultType]::ParameterName, 'Disable ANSI colors (also respects NO_COLOR)')
            [CompletionResult]::new('-h', 'h', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
            [CompletionResult]::new('--help', 'help', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
            [CompletionResult]::new('-V', 'V ', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('--version', 'version', [CompletionResultType]::ParameterName, 'Print version')
            break
        }
        'starman;doctor' {
            [CompletionResult]::new('--no-color', 'no-color', [CompletionResultType]::ParameterName, 'Disable ANSI colors (also respects NO_COLOR)')
            [CompletionResult]::new('-h', 'h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', 'help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('-V', 'V ', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('--version', 'version', [CompletionResultType]::ParameterName, 'Print version')
            break
        }
        'starman;create-user' {
            [CompletionResult]::new('-g', 'g', [CompletionResultType]::ParameterName, '协作 UNIX 组（默认见配置 `default_user_group`，一般为 lab）')
            [CompletionResult]::new('--group', 'group', [CompletionResultType]::ParameterName, '协作 UNIX 组（默认见配置 `default_user_group`，一般为 lab）')
            [CompletionResult]::new('--shell', 'shell', [CompletionResultType]::ParameterName, '登录 shell（默认见配置 `default_shell`）')
            [CompletionResult]::new('--home-quota', 'home-quota', [CompletionResultType]::ParameterName, '家目录所在文件系统上的用户磁盘配额（软/硬相同，块配额）；如 `200G`、`500M`。默认 200G，见配置 `default_home_quota`')
            [CompletionResult]::new('--no-brew', 'no-brew', [CompletionResultType]::ParameterName, '不初始化 Linuxbrew（跳过 `brew bundle`）')
            [CompletionResult]::new('--no-quota', 'no-quota', [CompletionResultType]::ParameterName, '不设置磁盘配额（忽略默认 200G）')
            [CompletionResult]::new('--no-color', 'no-color', [CompletionResultType]::ParameterName, 'Disable ANSI colors (also respects NO_COLOR)')
            [CompletionResult]::new('-h', 'h', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('--help', 'help', [CompletionResultType]::ParameterName, 'Print help')
            [CompletionResult]::new('-V', 'V ', [CompletionResultType]::ParameterName, 'Print version')
            [CompletionResult]::new('--version', 'version', [CompletionResultType]::ParameterName, 'Print version')
            break
        }
        'starman;help' {
            [CompletionResult]::new('tui', 'tui', [CompletionResultType]::ParameterValue, 'Interactive full-screen TUI (requires a TTY on stdout)')
            [CompletionResult]::new('version', 'version', [CompletionResultType]::ParameterValue, 'Print version and exit')
            [CompletionResult]::new('completion', 'completion', [CompletionResultType]::ParameterValue, 'Print shell completion script to stdout (redirect or eval — see long help)')
            [CompletionResult]::new('doctor', 'doctor', [CompletionResultType]::ParameterValue, 'Check paths, config, and basic environment')
            [CompletionResult]::new('create-user', 'create-user', [CompletionResultType]::ParameterValue, 'Create a UNIX user with shell snippets, optional group & Linuxbrew (requires root)')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
            break
        }
        'starman;help;tui' {
            break
        }
        'starman;help;version' {
            break
        }
        'starman;help;completion' {
            break
        }
        'starman;help;doctor' {
            break
        }
        'starman;help;create-user' {
            break
        }
        'starman;help;help' {
            break
        }
    })

    $completions.Where{ $_.CompletionText -like "$wordToComplete*" } |
        Sort-Object -Property ListItemText
}
