param(
    [Parameter(Mandatory = $true)]
    [string]$InstallParent
)

$ErrorActionPreference = 'Stop'
$Version = '3.44.7'
$Archive = 'flutter_windows_3.44.7-stable.zip'
$ExpectedSha256 = '327b89c2ff612418c1d756efc9636d7811c50e4b50a916d07bc3bdc317ba25e5'
$BaseUrl = 'https://storage.googleapis.com/flutter_infra_release/releases'
$FlutterPath = Join-Path $InstallParent 'flutter'

if (Test-Path $FlutterPath) {
    throw "Refusing to overwrite existing path: $FlutterPath"
}

New-Item -ItemType Directory -Path $InstallParent -Force | Out-Null
$DownloadDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
New-Item -ItemType Directory -Path $DownloadDirectory | Out-Null

try {
    $ArchivePath = Join-Path $DownloadDirectory $Archive
    Invoke-WebRequest -Uri "$BaseUrl/stable/windows/$Archive" -OutFile $ArchivePath
    $ActualSha256 = (Get-FileHash -Path $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ActualSha256 -ne $ExpectedSha256) {
        throw "SHA-256 mismatch for $Archive. Expected $ExpectedSha256, found $ActualSha256."
    }

    Expand-Archive -Path $ArchivePath -DestinationPath $InstallParent
    $VersionOutput = & (Join-Path $FlutterPath 'bin/flutter.bat') --version --machine |
        ConvertFrom-Json
    $ActualVersion = $VersionOutput.flutterVersion
    if (-not $ActualVersion) {
        $ActualVersion = $VersionOutput.frameworkVersion
    }
    if ($ActualVersion -ne $Version) {
        throw "Expected Flutter $Version, found $ActualVersion."
    }
} finally {
    Remove-Item -Path $DownloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Installed verified Flutter $Version at $FlutterPath"
