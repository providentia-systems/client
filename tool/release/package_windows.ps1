[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$PackageIdentityName,
    [Parameter(Mandatory = $true)][string]$Publisher,
    [Parameter(Mandatory = $true)][string]$PfxPath,
    [Parameter(Mandatory = $true)][string]$PfxPassword,
    [Parameter(Mandatory = $true)][string]$ExpectedThumbprint
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)(?:[-+][0-9A-Za-z.-]+)?$') {
    throw 'Version must be a semantic version without a v prefix.'
}
$versionMajor = [int]$Matches[1]
$versionMinor = [int]$Matches[2]
$versionPatch = [int]$Matches[3]
if ($versionMajor -gt 65535 -or $versionMinor -gt 65535 -or $versionPatch -gt 65535) {
    throw 'MSIX version components must not exceed 65535.'
}
if ($PackageIdentityName -notmatch '^[A-Za-z0-9.-]+$') {
    throw 'MSIX package identity may contain only letters, digits, periods and hyphens.'
}
if (-not (Test-Path -LiteralPath (Join-Path $BundleDirectory 'Providentia.exe') -PathType Leaf)) {
    throw 'The Flutter Windows release bundle does not contain Providentia.exe.'
}
if (-not (Test-Path -LiteralPath $PfxPath -PathType Leaf)) {
    throw 'The protected Windows signing certificate is missing.'
}

$certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $PfxPath,
    $PfxPassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
)
$actualThumbprint = ($certificate.Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
$expected = ($ExpectedThumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
if ($expected.Length -ne 40 -or $actualThumbprint -ne $expected) {
    throw 'The Windows signing certificate thumbprint does not match the protected release identity.'
}
if (-not [string]::Equals($certificate.Subject, $Publisher, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Certificate subject '$($certificate.Subject)' does not equal MSIX publisher '$Publisher'."
}

$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$sdkBin = Get-ChildItem -LiteralPath $sdkRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64\makeappx.exe') } |
    Sort-Object Name -Descending |
    Select-Object -First 1
if ($null -eq $sdkBin) {
    throw 'Windows SDK makeappx.exe and signtool.exe are required.'
}
$makeAppx = Join-Path $sdkBin.FullName 'x64\makeappx.exe'
$signTool = Join-Path $sdkBin.FullName 'x64\signtool.exe'

$work = Join-Path $env:RUNNER_TEMP ([System.Guid]::NewGuid().ToString('N'))
$layout = Join-Path $work 'layout'
$appDirectory = Join-Path $layout 'Providentia'
$assets = Join-Path $layout 'Assets'
New-Item -ItemType Directory -Path $appDirectory, $assets, $OutputDirectory -Force | Out-Null
Copy-Item -Path (Join-Path $BundleDirectory '*') -Destination $appDirectory -Recurse -Force

Add-Type -AssemblyName System.Drawing
$sourceIcon = Join-Path $PSScriptRoot '..\..\web\icons\Icon-512.png'
foreach ($asset in @(
    @{Name = 'Square44x44Logo.png'; Size = 44},
    @{Name = 'Square150x150Logo.png'; Size = 150},
    @{Name = 'StoreLogo.png'; Size = 50}
)) {
    $source = [System.Drawing.Image]::FromFile($sourceIcon)
    try {
        $bitmap = [System.Drawing.Bitmap]::new($source, $asset.Size, $asset.Size)
        try {
            $bitmap.Save((Join-Path $assets $asset.Name), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bitmap.Dispose()
        }
    } finally {
        $source.Dispose()
    }
}

$buildNumber = if ($env:GITHUB_RUN_NUMBER -match '^\d+$') { [int]$env:GITHUB_RUN_NUMBER % 65535 } else { 1 }
$msixVersion = "$versionMajor.$versionMinor.$versionPatch.$buildNumber"
$escapedIdentity = [System.Security.SecurityElement]::Escape($PackageIdentityName)
$escapedPublisher = [System.Security.SecurityElement]::Escape($Publisher)
$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$escapedIdentity" Publisher="$escapedPublisher" Version="$msixVersion" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Providentia</DisplayName>
    <PublisherDisplayName>Vast Development Method</PublisherDisplayName>
    <Description>Providentia household stock control client</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Resources><Resource Language="en-us" /></Resources>
  <Applications>
    <Application Id="Providentia" Executable="Providentia\Providentia.exe" EntryPoint="Windows.FullTrustApplication"
                 uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="Providentia" Description="Providentia household stock control client"
                          BackgroundColor="transparent" Square150x150Logo="Assets\Square150x150Logo.png"
                          Square44x44Logo="Assets\Square44x44Logo.png" />
    </Application>
  </Applications>
  <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
"@
[System.IO.File]::WriteAllText((Join-Path $layout 'AppxManifest.xml'), $manifest, [System.Text.UTF8Encoding]::new($false))

$outputFile = Join-Path $OutputDirectory "Providentia-$Version-x64.msix"
& $makeAppx pack /d $layout /p $outputFile /o
if ($LASTEXITCODE -ne 0) { throw 'makeappx failed.' }
& $signTool sign /fd SHA256 /f $PfxPath /p $PfxPassword $outputFile
if ($LASTEXITCODE -ne 0) { throw 'signtool signing failed.' }
& $signTool verify /pa /all /v $outputFile
if ($LASTEXITCODE -ne 0) { throw 'signtool verification failed.' }

$signature = Get-AuthenticodeSignature -LiteralPath $outputFile
if ($signature.Status -ne 'Valid') {
    throw "MSIX Authenticode status is $($signature.Status), not Valid."
}
Remove-Item -LiteralPath $work -Recurse -Force
