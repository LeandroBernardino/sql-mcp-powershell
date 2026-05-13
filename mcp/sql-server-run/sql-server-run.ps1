#requires -Version 5.1
<#
  MCP (stdio, JSON-RPC) over sqlcmd only. Env:
  SQL_MCP_WORKSPACE_ROOT (or WORKSPACE_FOLDER) locates workspace; optional .env there sets:
  SQL_SERVER / SQL_DATABASE / SQL_TRUST_CERT (friendly names), or
  SQLCMDSERVER, SQLCMDDATABASE, SQLCMD_TRUST_CERT (sqlcmd names). SQLCMDUSER/SQLCMDPASSWORD still from process env if set elsewhere.
  SQLCMD_TRUST_CERT: set "0" to omit sqlcmd -C; unset or other values add -C.
#>
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Send-McpLine {
    param([hashtable]$Object)
    $json = $Object | ConvertTo-Json -Compress -Depth 30
    [Console]::Out.WriteLine($json)
}

function Get-WorkspaceRoot {
    if ($env:SQL_MCP_WORKSPACE_ROOT) {
        return (Resolve-Path -LiteralPath $env:SQL_MCP_WORKSPACE_ROOT -ErrorAction Stop).Path
    }
    if ($env:WORKSPACE_FOLDER) {
        return (Resolve-Path -LiteralPath $env:WORKSPACE_FOLDER -ErrorAction Stop).Path
    }
    return (Get-Location).Path
}

function Import-WorkspaceDotEnv {
    $root = Get-WorkspaceRoot
    $path = Join-Path $root '.env'
    if (-not (Test-Path -LiteralPath $path)) { return }

    $apply = {
        param([string]$Name, [string]$Value)
        switch ($Name) {
            'SQL_SERVER' { $env:SQLCMDSERVER = $Value; break }
            'SQL_DATABASE' { $env:SQLCMDDATABASE = $Value; break }
            'SQL_TRUST_CERT' { $env:SQLCMD_TRUST_CERT = $Value; break }
            'SQLCMDSERVER' { $env:SQLCMDSERVER = $Value; break }
            'SQLCMDDATABASE' { $env:SQLCMDDATABASE = $Value; break }
            'SQLCMD_TRUST_CERT' { $env:SQLCMD_TRUST_CERT = $Value; break }
            default { }
        }
    }

    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $name = $t.Substring(0, $eq).Trim()
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
        $raw = $t.Substring($eq + 1).Trim()
        $value = $raw
        if ($raw.Length -ge 2) {
            $q0 = $raw[0]
            $q1 = $raw[$raw.Length - 1]
            if (($q0 -eq '"' -and $q1 -eq '"') -or ($q0 -eq "'" -and $q1 -eq "'")) {
                $value = $raw.Substring(1, $raw.Length - 2)
            }
        }
        & $apply -Name $name -Value $value
    }
}

function Build-SqlcmdArgs {
    param([string]$Database)
    $server = if ($env:SQLCMDSERVER) { $env:SQLCMDSERVER } else { 'localhost' }
    $db = if ($Database) { $Database }
    elseif ($env:SQLCMDDATABASE) { $env:SQLCMDDATABASE }
    else { 'ads_portal' }
    $list = [System.Collections.Generic.List[string]]::new()
    [void]$list.AddRange([string[]]@('-S', $server, '-d', $db, '-b', '-I', '-W'))
    if ($env:SQLCMD_TRUST_CERT -ne '0') { [void]$list.Add('-C') }
    if ($env:SQLCMDUSER) {
        $pwd = if ($null -ne $env:SQLCMDPASSWORD) { $env:SQLCMDPASSWORD } else { '' }
        [void]$list.AddRange([string[]]@('-U', $env:SQLCMDUSER, '-P', $pwd))
    }
    else {
        [void]$list.Add('-E')
    }
    return $list.ToArray()
}

function Invoke-SqlcmdProcess {
    param([string[]]$ArgumentList)
    $outFile = [System.IO.Path]::GetTempFileName() + '-stdout.txt'
    $errFile = [System.IO.Path]::GetTempFileName() + '-stderr.txt'
    try {
        $p = Start-Process -FilePath 'sqlcmd' -ArgumentList $ArgumentList -Wait -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $stdout = [System.IO.File]::ReadAllText($outFile)
        $stderr = [System.IO.File]::ReadAllText($errFile)
        return @{
            Ok         = ($p.ExitCode -eq 0)
            ExitCode   = $p.ExitCode
            Stdout     = $stdout
            Stderr     = $stderr
        }
    }
    finally {
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-PathInsideWorkspace {
    param([string]$Candidate, [string]$Root)
    $c = [System.IO.Path]::GetFullPath($Candidate)
    $r = [System.IO.Path]::GetFullPath($Root)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $prefix = if ($r.EndsWith($sep)) { $r } else { $r + $sep }
    if ($c.Equals($r, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $c.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ToolsListPayload {
    return @{
        tools = @(
            @{
                name        = 'execute_sql'
                description = 'Run T-SQL via sqlcmd (-i temp file, GO allowed). Optional database overrides SQLCMDDATABASE.'
                inputSchema = @{
                    type       = 'object'
                    properties = @{
                        sql      = @{ type = 'string'; description = 'Full script or batch' }
                        database = @{ type = 'string'; description = 'Initial database (-d).' }
                    }
                    required   = @('sql')
                }
            },
            @{
                name        = 'execute_sql_file'
                description = 'Run a workspace .sql file via sqlcmd -i. Path relative to SQL_MCP_WORKSPACE_ROOT.'
                inputSchema = @{
                    type       = 'object'
                    properties = @{
                        relative_path = @{ type = 'string'; description = 'e.g. back-end/schema.sql' }
                        database      = @{ type = 'string'; description = 'Initial database (-d). Optional.' }
                    }
                    required   = @('relative_path')
                }
            }
        )
    }
}

function Invoke-ToolCall {
    param([string]$ToolName, $Arguments)
    $root = Get-WorkspaceRoot
    $db = $null
    if ($Arguments -and $Arguments.PSObject.Properties['database']) {
        $v = $Arguments.database
        if ($null -ne $v -and "$v".Trim()) { $db = "$v".Trim() }
    }

    if ($ToolName -eq 'execute_sql') {
        if (-not $Arguments -or -not $Arguments.PSObject.Properties['sql']) {
            return @{ content = @(@{ type = 'text'; text = 'Missing sql' }); isError = $true }
        }
        $sql = [string]$Arguments.sql
        if (-not $sql.Trim()) {
            return @{ content = @(@{ type = 'text'; text = 'Empty sql' }); isError = $true }
        }
        $tmp = [System.IO.Path]::GetTempFileName() + '.sql'
        $enc = New-Object System.Text.UTF8Encoding $true
        $body = if ($sql.StartsWith([char]0xFEFF)) { $sql } else { [char]0xFEFF + $sql }
        try {
            [System.IO.File]::WriteAllText($tmp, $body, $enc)
            $baseArgs = Build-SqlcmdArgs -Database $db
            $allArgs = [string[]]($baseArgs + @('-i', $tmp))
            $out = Invoke-SqlcmdProcess -ArgumentList $allArgs
        }
        finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        $text = @(
            $(if ($out.Ok) { 'OK' } else { "FAILED (exit $($out.ExitCode))" }),
            '--- stdout ---',
            $(if ($out.Stdout) { $out.Stdout } else { '(empty)' }),
            '--- stderr ---',
            $(if ($out.Stderr) { $out.Stderr } else { '(empty)' })
        ) -join "`n"
        return @{ content = @(@{ type = 'text'; text = $text }); isError = (-not $out.Ok) }
    }

    if ($ToolName -eq 'execute_sql_file') {
        if (-not $Arguments -or -not $Arguments.PSObject.Properties['relative_path']) {
            return @{ content = @(@{ type = 'text'; text = 'Missing relative_path' }); isError = $true }
        }
        $rel = [string]$Arguments.relative_path
        if (-not $rel.Trim()) {
            return @{ content = @(@{ type = 'text'; text = 'Empty relative_path' }); isError = $true }
        }
        $relNorm = $rel -replace '/', [System.IO.Path]::DirectorySeparatorChar
        $abs = [System.IO.Path]::GetFullPath((Join-Path $root $relNorm))
        if (-not (Test-PathInsideWorkspace -Candidate $abs -Root $root)) {
            return @{ content = @(@{ type = 'text'; text = "Path escapes workspace: $rel" }); isError = $true }
        }
        if (-not (Test-Path -LiteralPath $abs)) {
            return @{ content = @(@{ type = 'text'; text = "File not found: $abs" }); isError = $true }
        }
        $baseArgs = Build-SqlcmdArgs -Database $db
        $allArgs = [string[]]($baseArgs + @('-i', $abs))
        $out = Invoke-SqlcmdProcess -ArgumentList $allArgs
        $text = @(
            $(if ($out.Ok) { 'OK' } else { "FAILED (exit $($out.ExitCode))" }),
            '--- stdout ---',
            $(if ($out.Stdout) { $out.Stdout } else { '(empty)' }),
            '--- stderr ---',
            $(if ($out.Stderr) { $out.Stderr } else { '(empty)' })
        ) -join "`n"
        return @{ content = @(@{ type = 'text'; text = $text }); isError = (-not $out.Ok) }
    }

    return @{ content = @(@{ type = 'text'; text = "Unknown tool: $ToolName" }); isError = $true }
}

Import-WorkspaceDotEnv

# --- stdio loop ---
while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    $trim = $line.Trim()
    if (-not $trim) { continue }

    $msg = $null
    try {
        $msg = $trim | ConvertFrom-Json
    }
    catch {
        continue
    }

    $method = [string]$msg.method
    if (-not $method) { continue }

    # Notifications: no response
    if ($method.StartsWith('notifications/')) { continue }

    $hasId = $msg.PSObject.Properties.Name -contains 'id'
    $rid = if ($hasId) { $msg.id } else { $null }

    try {
        if ($method -eq 'initialize') {
            if (-not $hasId) { continue }
            $pv = '2024-11-05'
            if ($msg.params -and $msg.params.PSObject.Properties['protocolVersion']) {
                $pv = [string]$msg.params.protocolVersion
            }
            Send-McpLine @{
                jsonrpc = '2.0'
                id      = $rid
                result  = @{
                    protocolVersion = $pv
                    capabilities    = @{ tools = @{} }
                    serverInfo      = @{ name = 'sql-server-run'; version = '1.0.0' }
                }
            }
            continue
        }

        if ($method -eq 'tools/list') {
            if (-not $hasId) { continue }
            Send-McpLine @{
                jsonrpc = '2.0'
                id      = $rid
                result  = (Get-ToolsListPayload)
            }
            continue
        }

        if ($method -eq 'tools/call') {
            if (-not $hasId) { continue }
            $name = [string]$msg.params.name
            $args = $msg.params.arguments
            $result = Invoke-ToolCall -ToolName $name -Arguments $args
            Send-McpLine @{
                jsonrpc = '2.0'
                id      = $rid
                result  = $result
            }
            continue
        }

        if ($method -eq 'ping') {
            if (-not $hasId) { continue }
            Send-McpLine @{ jsonrpc = '2.0'; id = $rid; result = @{} }
            continue
        }

        if ($hasId) {
            Send-McpLine @{
                jsonrpc = '2.0'
                id      = $rid
                error   = @{
                    code    = -32601
                    message = "Method not found: $method"
                }
            }
        }
    }
    catch {
        if ($hasId) {
            Send-McpLine @{
                jsonrpc = '2.0'
                id      = $rid
                error   = @{
                    code    = -32603
                    message = $_.Exception.Message
                }
            }
        }
    }
}
