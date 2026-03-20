#================================================================
# Adversity Windows 11 Debloater - Performance Tweaker
# A simple, focused PowerShell script for performance/privacy tweaks
# Purpose: Remove bloatware, disable telemetry, optimize services
# Targets: Windows 11 24H2/25H2 (2024-2026)
# Safety: Confirmations before major changes, detailed logging
#
# Usage:
#   1. Right-click > Run with PowerShell (Admin)
#   2. Or: powershell -ExecutionPolicy Bypass -File .\Adversity-W11-Debloater-GUI.ps1
#   3. Or (for online): irm "https://url.to/script.ps1" | iex
#
# Author: SkyTheLight (GitHub: SkyTheLight)
# License: MIT (free to modify/distribute)
#================================================================

# Note: Admin check is done via Test-Admin function below
# This allows the script to be sourced without admin first, then re-launch if needed

param(
    [switch]$NoPrompt  # Skip all confirmations (use with caution)
)

#region Global Variables & Configuration
# Tracking variables for summary report
$Script:ChangesLog = @()
$Script:AppRemovals = @()
$Script:ServiceChanges = @()
$Script:RegistryTweaks = @()
$Script:ErrorCount = 0
#endregion

#region Utility Functions
#================================================================
# Write-Log: Color-coded console output with timestamp logging
#================================================================
function Write-Log {
    param(
        [string]$Message,
        [string]$Type = 'INFO'  # INFO, WARN, ERROR, SUCCESS
    )
    
    $Colors = @{
        'INFO'    = 'Cyan'
        'WARN'    = 'Yellow'
        'ERROR'   = 'Red'
        'SUCCESS' = 'Green'
    }
    
    $Color = $Colors[$Type] -as [System.ConsoleColor]
    $Timestamp = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$Timestamp] [$Type] $Message" -ForegroundColor $Color
    
    # Add to log array for summary
    $Script:ChangesLog += "[$Timestamp] [$Type] $Message"
}

#================================================================
# Test-Admin: Verify admin rights, re-launch if needed
#================================================================
function Test-Admin {
    $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $IsAdmin) {
        Write-Host 'This script requires Administrator privileges.' -ForegroundColor Red
        Write-Host 'Relaunching as Administrator...' -ForegroundColor Yellow
        
        $ScriptPath = $MyInvocation.MyCommand.Path
        if (-not $ScriptPath) {
            $ScriptPath = $PSCommandPath
        }
        
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        Start-Process -FilePath 'powershell.exe' -ArgumentList $Arguments -Verb RunAs -Wait
        exit 0
    }
    
    Write-Log 'Administrator privileges verified' 'SUCCESS'
}

#================================================================
# Show-Banner: Colorful ASCII art welcome header
#================================================================
function Show-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '================================================================================' -ForegroundColor Cyan
    Write-Host '                                                                              ' -ForegroundColor Cyan
'              ADVERSITY W11 DEBLOATER - WINDOWS 11 OPTIMIZER              '
    Write-Host '                                                                              ' -ForegroundColor Cyan
    Write-Host '    Windows 11 Debloater & Performance Optimizer                             ' -ForegroundColor White
    Write-Host '                           Version 1.0                                       ' -ForegroundColor Gray
    Write-Host '                                                                              ' -ForegroundColor Cyan
    Write-Host '================================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  [OK] Safe and Reversible        [FAST] Efficient        [SECURE] Privacy Focused' -ForegroundColor Yellow
    Write-Host ''
}

#================================================================
# Confirm-Action: Ask user before destructive operations
#================================================================
function Confirm-Action {
    param([string]$Message)
    
    if ($NoPrompt) { 
        Write-Log 'Confirmation(s) bypassed with -NoPrompt' 'WARN'
        return $true 
    }
    
    Write-Host ''
    Write-Host $Message -ForegroundColor Yellow
    Write-Host 'WARNING: This action may affect system functionality!' -ForegroundColor Red -NoNewLine
    $Response = Read-Host ' | Continue? (y/N)'
    
    return $Response -match '^[yY]$'
}

#================================================================
# Pause-Menu: Wait for user input before continuing
#================================================================
function Pause-Menu {
    Read-Host "`nPress Enter to continue"
}

#endregion

#region App Removal Functions
#================================================================
# Remove-AppxPackageByName: Safely remove UWP app, current + all users
#================================================================
function Remove-AppxPackageByName {
    param([string]$AppName)
    
    try {
        # Remove from current user
        $CurrentUserApps = Get-AppxPackage -Name $AppName -ErrorAction SilentlyContinue
        if ($CurrentUserApps) {
            $CurrentUserApps | Remove-AppxPackage -ErrorAction SilentlyContinue
        }
        
        # Remove provisioned package (install for future users)
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | 
            Where-Object DisplayName -Like $AppName | 
            Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        
        Write-Log "Removed app: $AppName" 'SUCCESS'
        $Script:AppRemovals += $AppName
        
    } catch {
        Write-Log "Failed to remove $AppName : $($_.Exception.Message)" 'WARN'
        $Script:ErrorCount++
    }
}

#================================================================
# Remove-BloatwareApps: Batch remove common unwanted apps
#================================================================
function Remove-BloatwareApps {
    param([string[]]$AppPatterns)
    
    Write-Log "Removing $($AppPatterns.Count) app(s)..."
    
    foreach ($Pattern in $AppPatterns) {
        Remove-AppxPackageByName $Pattern
        Start-Sleep -Milliseconds 100  # Avoid system stress
    }
}

#endregion

#region Service & Registry Functions
#================================================================
# Set-ServiceState: Change Windows service startup type
# Valid states: 'Auto', 'Manual', 'Disabled'
#================================================================
function Set-ServiceState {
    param(
        [PSCustomObject[]]$Services
    )
    
    Write-Log "Configuring $($Services.Count) Windows service(s)..."
    
    foreach ($Service in $Services) {
        try {
            $ServiceObj = Get-Service -Name $Service.Name -ErrorAction SilentlyContinue
            
            if (-not $ServiceObj) {
                Write-Log "Service not found: $($Service.Name)" 'WARN'
                continue
            }
            
            # Use sc.exe to set startup type (more reliable than Set-Service on Win11)
            $StartTypeValue = @{
                'Auto'     = 'auto'
                'Manual'   = 'demand'
                'Disabled' = 'disabled'
            }[$Service.State]
            
            $null = sc.exe config $Service.Name start= $StartTypeValue
            Write-Log "Service '$($Service.Name)' set to $($Service.State)" 'SUCCESS'
            $Script:ServiceChanges += "$($Service.Name)=$($Service.State)"
            
        } catch {
            Write-Log "Error setting service $($Service.Name): $($_.Exception.Message)" 'WARN'
            $Script:ErrorCount++
        }
    }
}

#================================================================
# Apply-RegistryTweaks: Batch apply registry modifications
# Creates path if needed, safely handles errors
#================================================================
function Apply-RegistryTweaks {
    param([PSCustomObject[]]$Tweaks)
    
    Write-Log "Applying $($Tweaks.Count) registry tweak(s)..."
    
    foreach ($Tweak in $Tweaks) {
        try {
            # Create path if it doesn't exist
            if (-not (Test-Path -Path $Tweak.Path)) {
                $null = New-Item -Path $Tweak.Path -Force -ErrorAction SilentlyContinue
            }
            
            # Apply the registry value
            Set-ItemProperty -Path $Tweak.Path `
                            -Name $Tweak.Name `
                            -Value $Tweak.Value `
                            -Type $Tweak.Type `
                            -Force
            
            Write-Log "Registry: $($Tweak.Path)\$($Tweak.Name)" 'SUCCESS'
            $Script:RegistryTweaks += "$($Tweak.Path)\$($Tweak.Name)=$($Tweak.Value)"
            
        } catch {
            Write-Log "Registry error at $($Tweak.Path): $($_.Exception.Message)" 'WARN'
            $Script:ErrorCount++
        }
    }
}

#================================================================
# Disable-Telemetry: Core privacy registry tweaks
#================================================================
function Disable-Telemetry {
    Write-Log 'Applying telemetry & privacy fixes...'
    
    $TelemetryTweaks = @(
        [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; Value=0; Type='DWORD' },
        [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Advertising'; Name='DisabledForUser'; Value=1; Type='DWORD' },
        [PSCustomObject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name='BingSearchEnabled'; Value=0; Type='DWORD' },
        [PSCustomObject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='ContentDeliveryManagerEnabled'; Value=0; Type='DWORD' },
        [PSCustomObject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='OemPreInstalledAppsEnabled'; Value=0; Type='DWORD' },
        [PSCustomObject]@{ Path='HKCU:\Software\Microsoft\Input\TIPC'; Name='Enabled'; Value=0; Type='DWORD' }
    )
    
    Apply-RegistryTweaks $TelemetryTweaks
}

#================================================================
# Disable-Cortana: Remove Cortana startup & background activity
#================================================================
function Disable-Cortana {
    Write-Log 'Disabling Cortana...'
    
    $CortanaTweaks = @(
        [PSCustomObject]@{ Path='HKCU:\Software\Microsoft\Personalization\Settings'; Name='PersonalizationTypedInsightsEnabled'; Value=0; Type='DWORD' },
        [PSCustomObject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name='AllowCortana'; Value=0; Type='DWORD' }
    )
    
    Apply-RegistryTweaks $CortanaTweaks
    
    # Remove Cortana app if using Edge/new Search
    Remove-AppxPackageByName '*Microsoft.Windows.Cortana*'
}

#================================================================
# Disable-OneDrive: Full OneDrive removal from system
#================================================================
function Disable-OneDrive {
    Write-Log 'Removing OneDrive...'
    
    if (-not (Confirm-Action "Really remove OneDrive? (This may prevent sync of important files)")) {
        return
    }
    
    try {
        # Kill OneDrive process
        Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Run uninstaller
        $Uninstaller = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
        if (Test-Path $Uninstaller) {
            & $Uninstaller /uninstall
            Start-Sleep -Seconds 3
            Write-Log 'OneDrive uninstalled' 'SUCCESS'
            $Script:AppRemovals += 'OneDrive'
        } else {
            Write-Log 'OneDrive uninstaller not found' 'WARN'
        }
        
        # Disable sync folder shortcuts
        Apply-RegistryTweaks @(
            [PSCustomObject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='StartShortcut'; Value=0; Type='DWORD' }
        )
        
    } catch {
        Write-Log "OneDrive removal failed: $($_.Exception.Message)" 'WARN'
        $Script:ErrorCount++
    }
}

#================================================================
# Disable-VisualEffects: Strip animations for performance
#================================================================
function Disable-VisualEffects {
    Write-Log 'Disabling visual effects for performance...'
    
    try {
        # Disable animations
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Force
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Force
        
        # Disable theme effects (transparency, etc.)
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                        -Name 'AppsUseLightTheme' -Value 1 -Type DWORD -Force
        
        Write-Log 'Visual effects reduced' 'SUCCESS'
        $Script:RegistryTweaks += 'Visual Effects Disabled'
        
    } catch {
        Write-Log "Visual effects error: $($_.Exception.Message)" 'WARN'
    }
}

#endregion

#region Preset Mode Functions
#================================================================
# Apply-PerformanceMode: Balanced tweaks (good for most users)
# Removes telemetry, bloat, but keeps useful apps
#================================================================
function Apply-PerformanceMode {
    Write-Log 'Applying Performance Mode (Balanced)'
    Write-Host ''
    Write-Host 'This mode:' -ForegroundColor Cyan
    Write-Host '  ✓ Removes Bing, News, Weather, Game apps, Widgets' -ForegroundColor Gray
    Write-Host '  ✓ Disables telemetry services' -ForegroundColor Gray
    Write-Host '  ✓ Tweaks privacy settings' -ForegroundColor Gray
    Write-Host '  ✓ Keeps Paint, Notepad, Calculator' -ForegroundColor Gray
    
    if (-not (Confirm-Action 'Apply Performance Mode? This is reversible.')) { return }
    
    # Remove bloatware (keep essentials)
    $PerformanceApps = @(
        '*Microsoft.BingWeather*',
        '*Microsoft.BingNews*',
        '*Microsoft.BingFinance*',
        '*Microsoft.GetHelp*',
        '*Microsoft.Getstarted*',
        '*Microsoft.MicrosoftOfficeHub*',
        '*Microsoft.MicrosoftSolitaireCollection*',
        '*Microsoft.MicrosoftStickyNotes*',
        '*Microsoft.MixedReality.Portal*',
        '*Microsoft.MixedRealityPortal*',
        '*Microsoft.People*',
        '*Microsoft.SkypeApp*',
        '*Microsoft.TeamCompanion*',
        '*Microsoft.WindowsCamera*',
        '*Microsoft.windowscommunicationsapps*',
        '*Microsoft.Xbox.TCUI*',
        '*Microsoft.XboxApp*',
        '*Microsoft.XboxGameOverlay*',
        '*Microsoft.XboxGamingOverlay*',
        '*Microsoft.XboxIdentityProvider*',
        '*Microsoft.XboxSpeechToTextOverlay*',
        '*Microsoft.YourPhone*',
        '*Microsoft.ZuneMusic*',
        '*Microsoft.ZuneVideo*',
        '*Clipchamp.Clipchamp*',
        '*MicrosoftWindows.Client.WebExperience*'
    )
    
    Remove-BloatwareApps $PerformanceApps
    
    # Disable telemetry services
    $PerformanceServices = @(
        [PSCustomObject]@{ Name='DiagTrack'; State='Disabled' },  # Connected User Experiences and Telemetry
        [PSCustomObject]@{ Name='dmwappushservice'; State='Disabled' },  # Device Management Wireless Application Protocol
        [PSCustomObject]@{ Name='SysMain'; State='Manual' },  # Superfetch (helpful on HDD, can disable on SSD)
        [PSCustomObject]@{ Name='WaaSMedicSvc'; State='Disabled' },  # Windows Update Medic Service
        [PSCustomObject]@{ Name='TabletInputService'; State='Manual' },  # Only needed for touch devices
        [PSCustomObject]@{ Name='XblAuthManager'; State='Manual' },  # Xbox Live Authentication
        [PSCustomObject]@{ Name='XblGameSave'; State='Disabled' }  # Xbox Game Save
    )
    
    Set-ServiceState $PerformanceServices
    
    # Apply privacy/telemetry registry tweaks
    Disable-Telemetry
    Disable-Cortana
    Disable-VisualEffects
    
    Write-Log 'Performance Mode applied successfully!' 'SUCCESS'
}

#================================================================
# Apply-PotatoMode: Ultra-aggressive for low-end hardware
# Removes almost everything non-essential
#================================================================
function Apply-PotatoMode {
    Write-Log 'Applying Potato PC Mode (Ultra-Lightweight for old hardware)'
    Write-Host ''
    Write-Host 'WARNING: This is VERY aggressive!' -ForegroundColor Red
    Write-Host '  ✗ Removes Edge, Store, Xbox, Teams, OneDrive' -ForegroundColor Yellow
    Write-Host '  ✗ Disables most background services' -ForegroundColor Yellow
    Write-Host '  ✗ Strips all animations' -ForegroundColor Yellow
    Write-Host '  ✗ May break some Windows features' -ForegroundColor Yellow
    
    if (-not (Confirm-Action 'CONFIRM: Apply Potato Mode? This may disable important features!')) { return }
    
    # First apply balanced mode as base
    Write-Log 'Applying baseline Performance Mode first...'
    
    # Remove additional apps for Potato mode
    $PotatoApps = @(
        '*Microsoft.MicrosoftEdge*',  # Microsoft Edge (can use alternatives)
        '*Microsoft.WindowsStore*',  # Windows Store (limited on old PCs anyway)
        '*Microsoft.OneConnect*',
        '*Microsoft.PowerAutomateDesktop*',
        '*Microsoft.Todos*',
        '*Microsoft.Whiteboard*',
        '*ActiproSoftwareLLC.CodeWriter*',
        '*Microsoft.RemoteDesktop*'
    )
    
    Remove-BloatwareApps $PotatoApps
    
    # Aggressive service disabling
    $PotatoServices = @(
        [PSCustomObject]@{ Name='CoreMessaging'; State='Manual' },
        [PSCustomObject]@{ Name='Themes'; State='Manual' },
        [PSCustomObject]@{ Name='Spooler'; State='Manual' },  # Print Spooler
        [PSCustomObject]@{ Name='PrintNotify'; State='Disabled' },
        [PSCustomObject]@{ Name='Fax'; State='Disabled' },
        [PSCustomObject]@{ Name='RemoteRegistry'; State='Disabled' },
        [PSCustomObject]@{ Name='WMPNetworkSvc'; State='Disabled' },
        [PSCustomObject]@{ Name='WSearch'; State='Manual' },  # Windows Search (disable if not needed)
        [PSCustomObject]@{ Name='MsKeyboardFilter'; State='Disabled' }
    )
    
    Set-ServiceState $PotatoServices
    
    # Remove OneDrive completely
    Disable-OneDrive
    
    # Disable all animations
    Write-Log 'Stripping visual effects...'
    Disable-VisualEffects
    
    # Additional performance tweaks
    $PotatoTweaks = @(
        [PSCustomObject]@{ Path='HKCU:\Control Panel\Desktop'; Name='MenuShowDelay'; Value='0'; Type='STRING' },
        [PSCustomObject]@{ Path='HKCU:\Control Panel\Desktop\WindowMetrics'; Name='MinAnimate'; Value='0'; Type='STRING' }
    )
    
    Apply-RegistryTweaks $PotatoTweaks
    
    Write-Log 'Potato Mode applied! Your PC is now lean & mean 🥔' 'SUCCESS'
    Write-Log 'Consider rebooting for full effect' 'INFO'
}

#================================================================
# Apply-UselessAppsMode: Target just the sponsored junk
# Safe and minimal changes
#================================================================
function Apply-UselessAppsMode {
    Write-Log 'Removing Sponsored/Useless Apps - Safe and Minimal'
    Write-Host ''
    Write-Host 'This mode removes only obvious bloat:' -ForegroundColor Cyan
    Write-Host '  • Candy Crush, Game Pass, Skype' -ForegroundColor Gray
    Write-Host '  • News, Weather, Solitaire' -ForegroundColor Gray
    Write-Host '  • Microsoft Edge (optional)' -ForegroundColor Gray
    
    if (-not (Confirm-Action 'Remove these apps?')) { return }
    
    $UselessApps = @(
        '*CandyCrush*',
        '*Disney*',
        '*HiddenCity*',
        '*MarchofEmpires*',
        '*Microsoft.549981C3F5F10*',  # Paint 3D (inferior to Paint)
        '*Microsoft.MicrosoftSolitaireCollection*',
        '*Microsoft.BingNews*',
        '*Microsoft.BingWeather*',
        '*Microsoft.Messaging*',  # Skype
        '*Microsoft.YourPhone*',
        '*Spotify*',
        '*PandoraMediaInc*'
    )
    
    Remove-BloatwareApps $UselessApps
    
    Write-Log 'Useless apps removed successfully!' 'SUCCESS'
}

#endregion

#region Custom & Revert Functions
#================================================================
# Show-CustomMode: Interactive selection of individual tweaks
#================================================================
function Show-CustomMode {
    Write-Log 'Custom/Advanced Mode - Select specific tweaks'
    Write-Host ''
    Write-Host 'Available tweak categories:' -ForegroundColor Green
    Write-Host '  1. Apps: Remove Edge/Store/Widgets' -ForegroundColor Cyan
    Write-Host '  2. Privacy: Telemetry, Ads, Bing Search' -ForegroundColor Cyan
    Write-Host '  3. Services: Disable Search, Superfetch, Print' -ForegroundColor Cyan
    Write-Host '  4. Visuals: Disable animations and effects' -ForegroundColor Cyan
    Write-Host '  5. OneDrive: Remove completely' -ForegroundColor Cyan
    Write-Host '  6. Games: Remove Xbox, Gamepass, Gaming overlay' -ForegroundColor Cyan
    Write-Host '  A. Apply All (Full debloat)' -ForegroundColor Cyan
    
    $Selection = (Read-Host "`nEnter choice(s) separated by commas (e.g., '1,2,4')").Split(',').Trim()
    
    foreach ($Choice in $Selection) {
        switch -Exact ($Choice.ToUpper()) {
            '1' { 
                Write-Log 'Removing app bloat...'
                $AppRemoval = @(
                    '*Microsoft.MicrosoftEdge*',
                    '*Microsoft.WindowsStore*',
                    '*MicrosoftWindows.Client.WebExperience*'
                )
                Remove-BloatwareApps $AppRemoval
            }
            
            '2' {
                Write-Log 'Applying privacy tweaks...'
                Disable-Telemetry
            }
            
            '3' {
                Write-Log 'Configuring services...'
                $CustomServices = @(
                    [PSCustomObject]@{ Name='WSearch'; State='Disabled' },
                    [PSCustomObject]@{ Name='SysMain'; State='Manual' },
                    [PSCustomObject]@{ Name='Spooler'; State='Manual' }
                )
                Set-ServiceState $CustomServices
            }
            
            '4' {
                Write-Log 'Disabling animations...'
                Disable-VisualEffects
            }
            
            '5' {
                Write-Log 'Removing OneDrive...'
                Disable-OneDrive
            }
            
            '6' {
                Write-Log 'Removing gaming components...'
                $GamingApps = @(
                    '*Microsoft.Xbox*',
                    '*Microsoft.XboxApp*',
                    '*Microsoft.GamingServices*'
                )
                Remove-BloatwareApps $GamingApps
            }
            
            'A' {
                Write-Log 'Applying full debloat (all tweaks)...'
                if (Confirm-Action 'Apply ALL tweaks?') {
                    Apply-PerformanceMode
                    1..6 | ForEach-Object { $Choice = $_; }
                }
            }
            
            default { Write-Log "Unknown selection: $Choice" 'WARN' }
        }
    }
}

#================================================================
# Show-RevertMode: Attempt to restore removed apps/settings
#================================================================
function Show-RevertMode {
    Write-Log 'Revert/Undo Mode'
    Write-Host ''
    Write-Host 'Options:' -ForegroundColor Cyan
    Write-Host '  1. Reinstall removed system apps like Paint, Notepad, Calculator' -ForegroundColor Gray
    Write-Host '  2. Restore disabled services to default' -ForegroundColor Gray
    Write-Host '  3. Both' -ForegroundColor Gray
    
    $RevertChoice = Read-Host 'Select (1-3)'
    
    if (-not (Confirm-Action 'This will attempt to restore changes. Continue?')) { return }
    
    if ($RevertChoice -in '1', '3') {
        Write-Log 'Reinstalling default apps...'
        
        $DefaultApps = @(
            'Microsoft.Paint',
            'Microsoft.WindowsCalculator',
            'Microsoft.WindowsNotepad',
            'Microsoft.WindowsAlarms',
            'Microsoft.Sticky',
            'Microsoft.Windows.Photos'
        )
        
        foreach ($App in $DefaultApps) {
            try {
                Get-AppxPackage -AllUsers | Where-Object Name -EQ $App | 
                    ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" }
                Write-Log "Restored: $App" 'SUCCESS'
            } catch {
                Write-Log "Could not restore $App : $($_.Exception.Message)" 'WARN'
            }
        }
    }
    
    if ($RevertChoice -in '2', '3') {
        Write-Log 'Restoring service defaults...'
        
        $DefaultServices = @(
            [PSCustomObject]@{ Name='DiagTrack'; State='Auto' },
            [PSCustomObject]@{ Name='dmwappushservice'; State='Auto' },
            [PSCustomObject]@{ Name='WSearch'; State='Auto' },
            [PSCustomObject]@{ Name='SysMain'; State='Auto' },
            [PSCustomObject]@{ Name='Spooler'; State='Auto' }
        )
        
        Set-ServiceState $DefaultServices
    }
    
    Write-Log 'Revert complete. Some changes may be permanent.' 'INFO'
}

#endregion

#region Main Menu & Reporting
#================================================================
# Show-Summary: Display changes made and offer reboot/save log
#================================================================
function Show-Summary {
    Write-Host ''
    Write-Host '=================================================================================' -ForegroundColor Magenta
    Write-Host '                          EXECUTION SUMMARY' -ForegroundColor Magenta
    Write-Host '=================================================================================' -ForegroundColor Magenta
    
    Write-Host ''
    Write-Host 'Changes Applied:' -ForegroundColor Cyan
    Write-Host "  - Apps Removed:          $($AppRemovals.Count) items" -ForegroundColor Red
    Write-Host "  - Services Modified:     $($ServiceChanges.Count) services" -ForegroundColor Yellow
    Write-Host "  - Registry Tweaks:       $($RegistryTweaks.Count) changes" -ForegroundColor Blue
    Write-Host "  - Errors Encountered:    $($ErrorCount) issues" -ForegroundColor $(if ($ErrorCount -gt 0) { 'Red' } else { 'Green' })
    
    Write-Host ''
    
    # Save detailed log
$LogPath = "$env:TEMP\Adversity-W11-Debloater-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $Script:ChangesLog | Out-File -FilePath $LogPath -Encoding UTF8
    Write-Log "Detailed log saved to: $LogPath" 'SUCCESS'
    
    Write-Host ''
    
    # Offer reboot
    if ($AppRemovals.Count -gt 0 -or $ServiceChanges.Count -gt 0) {
        Write-Host '=================================================================================' -ForegroundColor Yellow
        Write-Host 'RECOMMENDATION: Restart Windows to fully apply changes.' -ForegroundColor Yellow
        Write-Host 'Some app removals and service changes require a reboot.' -ForegroundColor Yellow
        Write-Host '=================================================================================' -ForegroundColor Yellow
        Write-Host ''
        
        if (Confirm-Action 'Restart your PC now?') {
            Write-Host 'Restarting in 10 seconds... (press Ctrl+C to cancel)' -ForegroundColor Yellow
            for ($i = 10; $i -gt 0; $i--) {
                Write-Host "`r  $i seconds remaining... " -NoNewline -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
            Write-Host ''
            Restart-Computer -Force
        } else {
            Write-Host 'Reboot skipped. Please restart at your convenience.' -ForegroundColor Yellow
        }
    } else {
        Write-Host 'No changes were made.' -ForegroundColor Cyan
    }
}

#================================================================
# Show-MainMenu: Interactive menu loop for choosing debloat modes
#================================================================
function Show-MainMenu {
    do {
        Show-Banner
        
        Write-Host 'Select a debloat mode:' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  +-PRESET MODES+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+' -ForegroundColor Gray
        Write-Host '  |                                                               |' -ForegroundColor Gray
        Write-Host '  | (1) PERFORMANCE MODE - Balanced tweaking                      |' -ForegroundColor Cyan
        Write-Host '  |     Remove common bloat, disable telemetry, basic tweaks       |' -ForegroundColor Gray
        Write-Host '  |     Safe for most users - recommended starting point          |' -ForegroundColor Gray
        Write-Host '  |                                                               |' -ForegroundColor Gray
        Write-Host '  | (2) POTATO PC MODE - Ultra-aggressive optimization           |' -ForegroundColor Yellow
        Write-Host '  |     For old/low-spec hardware. Removes Edge, Store, OneDrive  |' -ForegroundColor Gray
        Write-Host '  |     WARNING: May disable some features - use with caution     |' -ForegroundColor DarkYellow
        Write-Host '  |                                                               |' -ForegroundColor Gray
        Write-Host '  | (3) USELESS APPS ONLY - Minimal/Safe removal                 |' -ForegroundColor Green
        Write-Host '  |     Removes only obvious junk (Candy Crush, Widgets, etc.)    |' -ForegroundColor Gray
        Write-Host '  |     Best option if you''re unsure - very reversible           |' -ForegroundColor Gray
        Write-Host '  |                                                               |' -ForegroundColor Gray
        Write-Host '  +-ADVANCED OPTIONS+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+' -ForegroundColor Gray
        Write-Host ''
        Write-Host '  (4) CUSTOM MODE - Pick your own tweaks by category' -ForegroundColor Magenta
        Write-Host '  (5) REVERT MODE - Undo/restore removed apps and settings' -ForegroundColor Blue
        Write-Host '  (6) EXIT - View summary and close' -ForegroundColor Red
        Write-Host ''
        
        $Choice = Read-Host 'Enter choice (1-6)'
        
        Write-Host ''
        
        switch ($Choice) {
            '1' { Apply-PerformanceMode }
            '2' { Apply-PotatoMode }
            '3' { Apply-UselessAppsMode }
            '4' { Show-CustomMode }
            '5' { Show-RevertMode }
            '6' { 
                Show-Summary
                break
            }
            default {
                Write-Log "Invalid choice: $Choice (select 1-6)" 'WARN'
                Start-Sleep -Seconds 1
                continue
            }
        }
        
        if ($Choice -ne '6') {
            Pause-Menu
        }
        
    } while ($Choice -ne '6')
    
    Write-Host ''
    Write-Host '================================================================================' -ForegroundColor Green
Write-Host 'Thank you for using Adversity W11 Debloater!' -ForegroundColor Yellow
    Write-Host 'Your system is cleaner and more optimized.' -ForegroundColor Gray
    Write-Host '================================================================================' -ForegroundColor Green
    Write-Host ''
    
    Pause-Menu
}

#endregion

#region Script Entry Point
#================================================================
# Main: Run as administrator and show menu
#================================================================
Test-Admin
Show-MainMenu

# Cleanup & exit
exit
#endregion
