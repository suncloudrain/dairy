# Prefer the local SDK. No global PATH or Git configuration is changed.
# Use raw arguments so PowerShell does not consume Flutter's -v / -d flags
# as its own common parameters (Verbose / Debug).
$FlutterArguments = $args

$projectRoot = Split-Path -Parent $PSScriptRoot
$localSdk = Join-Path $projectRoot '.tools/flutter'
$flutterCommand = Join-Path $localSdk 'bin/flutter.bat'
$useLocalSdk = Test-Path -LiteralPath $flutterCommand
if (-not $useLocalSdk) {
    $installedFlutter = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $installedFlutter) { throw 'Install Flutter or place it in .tools/flutter.' }
    $flutterCommand = $installedFlutter.Source
}

$savedEnvironment = @{}
function Set-ProcessValue([string]$Name, [string]$Value) {
    if (-not $savedEnvironment.ContainsKey($Name)) {
        $savedEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

$commandExitCode = 1
Push-Location -LiteralPath $projectRoot
try {
    Set-ProcessValue 'CI' 'true'
    if ($useLocalSdk) {
        Set-ProcessValue 'PUB_CACHE' (Join-Path $projectRoot '.tools/pub-cache')
        $configIndex = 0
        if ($env:GIT_CONFIG_COUNT) { $configIndex = [int]$env:GIT_CONFIG_COUNT }
        Set-ProcessValue "GIT_CONFIG_KEY_$configIndex" 'safe.directory'
        Set-ProcessValue "GIT_CONFIG_VALUE_$configIndex" $localSdk.Replace('\', '/')
        Set-ProcessValue 'GIT_CONFIG_COUNT' ([string]($configIndex + 1))
    }
    # Reuse the Windows system proxy if Dart has no proxy configured.
    if (-not $env:HTTPS_PROXY) {
        $target = [uri]'https://storage.googleapis.com'
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($target)
        if ($proxy -and $proxy.Authority -ne $target.Authority) {
            Set-ProcessValue 'HTTPS_PROXY' $proxy.AbsoluteUri
            if (-not $env:HTTP_PROXY) { Set-ProcessValue 'HTTP_PROXY' $proxy.AbsoluteUri }
        }
    }
    & $flutterCommand --suppress-analytics @FlutterArguments
    $commandExitCode = $LASTEXITCODE
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    Pop-Location
}
exit $commandExitCode
