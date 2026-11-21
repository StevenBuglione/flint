param([Parameter(Mandatory)][string]$CompletionFile)
$ErrorActionPreference = 'Stop'

function Register-ArgumentCompleter {
    param([switch]$Native, [string[]]$CommandName, [scriptblock]$ScriptBlock)
    if (!$Native) { throw 'Expected a native argument completer' }
    $script:registered = $CommandName
    $script:complete = $ScriptBlock
}

. $CompletionFile
if ($registered.Count -ne 1 -or $registered[0] -cne 'completion fixture') {
    throw 'Completion registration changed the command name'
}

function Read-Command([string]$Text) {
    $tokens = $null
    $errors = $null
    $syntax = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) { throw 'Generated completion could not be parsed' }
    return $syntax.EndBlock.Statements[0].PipelineElements[0]
}

$rootLine = "& 'completion fixture' --quo"
$items = @(& $script:complete '--quo' (Read-Command $rootLine) $rootLine.Length)
$quoted = @'
--quoted ' `touch FLINT_CLI_BACKTICK` $(touch FLINT_CLI_SUBSHELL) ’
'@
if ($items.Count -ne 1 -or $items[0].ListItemText -cne $quoted) {
    throw 'Candidate text changed'
}
$inserted = Read-Command ("& 'completion fixture' " + $items[0].CompletionText)
if ($inserted.CommandElements.Count -ne 2 -or
        $inserted.CommandElements[1] -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $inserted.CommandElements[1].Value -cne $quoted) {
    throw 'The completion insertion is not a single literal argument'
}

$childLine = "& 'completion fixture' 'child '' space' --le"
$child = @(& $script:complete '--le' (Read-Command $childLine) $childLine.Length)
if ($child.Count -ne 1 -or $child[0].ListItemText -cne '--leaf') {
    throw 'Child completion context changed'
}
if ((Test-Path FLINT_CLI_BACKTICK) -or (Test-Path FLINT_CLI_SUBSHELL)) {
    throw 'Generated completion executed fixture metadata'
}
Write-Output 'PowerShell: literal insertion and selected child context'
