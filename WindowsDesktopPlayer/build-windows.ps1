param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$Run
)

$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Install Visual Studio Build Tools with the C++ desktop workload.' }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'Install the .NET 8 SDK.' }
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $msbuild) { throw 'Visual Studio MSBuild with the C++ toolset was not found.' }

# Use Visual Studio MSBuild for C++, then the .NET CLI for WPF. Rebuild the
# native DLL so a previously successful managed build cannot retain an old one.
& $msbuild (Join-Path $PSScriptRoot 'native\WallpaperD3D.vcxproj') /t:Rebuild "/p:Configuration=$Configuration" /p:Platform=x64 /nologo
if ($LASTEXITCODE -ne 0) { throw 'Native wallpaper build failed.' }
& dotnet build (Join-Path $PSScriptRoot 'WindowsDesktopPlayer.csproj') --configuration $Configuration -p:SkipNativeBuild=true
if ($LASTEXITCODE -ne 0) { throw 'WPF player build failed.' }

$output = Join-Path $PSScriptRoot "bin\$Configuration\net8.0-windows"
Write-Host "Built Sound Desk: $output"
if ($Run) { Start-Process (Join-Path $output 'SoundDesk.exe') }
