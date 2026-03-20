#========================================================================
# Adversity Windows 11 Debloater GUI - Performance Optimizer
# 
# A modern, safe, and simple GUI-based debloater
#
# Features:
#   - Admin privilege enforcement
#   - Windows Forms GUI with dark mode
#   - Multiple preset modes + custom tweaks
#   - Real-time logging and progress tracking
#   - Safety confirmations and error handling
#   - Revert functionality for restoration
#
# Targets: Windows 11
# Author: SkyTheLight
# License: MIT (free to modify/distribute)
#========================================================================

param(
    [switch]$AdminBypass  # Skip admin check (for testing only)
)

#region Global Configuration
$Script:LogMessages = @()
$Script:WindowOpen = $true
$Script:AppsRemoved = 0
$Script:ServicesModified = 0
$Script:RegistryChanges = 0
$Script:ErrorCount = 0
$Script:IsProcessing = $false

# Colors now defined inside Create-MainForm after Add-Type

# Common apps to remove (pre-populated for Custom mode)
$CommonApps = @(
    @{ Name='Microsoft.BingWeather'; Display='Weather App' }
    @{ Name='Microsoft.BingNews'; Display='News App' }
    @{ Name='Microsoft.BingFinance'; Display='Finance App' }
    @{ Name='Clipchamp.Clipchamp'; Display='Clipchamp' }
    @{ Name='Microsoft.WindowsCamera'; Display='Camera' }
    @{ Name='Microsoft.ZuneMusic'; Display='Groove Music' }
    @{ Name='Microsoft.ZuneVideo'; Display='Movies & TV' }
    @{ Name='Microsoft.MicrosoftSolitaireCollection'; Display='Solitaire' }
    @{ Name='Microsoft.GetHelp'; Display='Get Help' }
    @{ Name='Microsoft.Getstarted'; Display='Get Started' }
    @{ Name='Microsoft.YourPhone'; Display='Phone Link' }
    @{ Name='Microsoft.SkypeApp'; Display='Skype' }
    @{ Name='Microsoft.TeamCompanion'; Display='Team Companion' }
    @{ Name='Microsoft.XboxApp'; Display='Xbox Console Companion' }
    @{ Name='Microsoft.Xbox.TCUI'; Display='Xbox Game UI' }
    @{ Name='Microsoft.XboxGameOverlay'; Display='Xbox Game Overlay' }
    @{ Name='Microsoft.XboxGamingOverlay'; Display='Xbox Gaming Overlay' }
    @{ Name='Microsoft.MicrosoftOfficeHub'; Display='Microsoft Office' }
    @{ Name='Microsoft.MixedReality.Portal'; Display='Mixed Reality Portal' }
)

# Services to manage
$ServicesList = @(
    @{ Name='DiagTrack'; Display='Connected User Experience'; Default='Manual' }
    @{ Name='dmwappushservice'; Display='Device Management'; Default='Manual' }
    @{ Name='SysMain'; Display='Superfetch (Sysmain)'; Default='Manual' }
    @{ Name='WaaSMedicSvc'; Display='Windows Update Medic'; Default='Manual' }
    @{ Name='WSearch'; Display='Windows Search'; Default='Auto' }
    @{ Name='Spooler'; Display='Print Spooler'; Default='Auto' }
    @{ Name='TabletInputService'; Display='Tablet Input'; Default='Manual' }
    @{ Name='XblAuthManager'; Display='Xbox Live Auth'; Default='Manual' }
    @{ Name='XblGameSave'; Display='Xbox Game Save'; Default='Manual' }
)

#endregion

#region Admin Check
function Test-AdminPrivileges {
    try {
        $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal(
            [Security.Principal.WindowsIdentity]::GetCurrent()
        )
        return $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Request-AdminPrivileges {
    if (Test-AdminPrivileges) { return }
    
    # Get script path
    $ScriptPath = $PSCommandPath
    if (-not $ScriptPath) { $ScriptPath = $MyInvocation.MyCommand.Path }
    
    # Re-launch as admin
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    try {
        Start-Process powershell.exe -ArgumentList $Arguments -Verb RunAs -Wait
        exit 0
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to elevate privileges: $($_.Exception.Message)",
            "Admin Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }
}

#endregion

#region Utility Functions
function Add-LogMessage {
    param([string]$Message, [string]$Type = 'INFO')
    
    $Timestamp = Get-Date -Format 'HH:mm:ss'
    $FullMessage = "[$Timestamp] [$Type] $Message"
    $Script:LogMessages += $FullMessage
    
    # Update UI if form exists
    if ($form -and $logTextBox) {
        $form.Invoke([System.Action] {
            $logTextBox.SelectionStart = $logTextBox.TextLength
            $logTextBox.SelectionLength = 0
            
            switch ($Type) {
                'ERROR' { $logTextBox.SelectionColor = $WarningRed }
                'SUCCESS' { $logTextBox.SelectionColor = $SuccessGreen }
                'WARN' { $logTextBox.SelectionColor = 'Yellow' }
                default { $logTextBox.SelectionColor = $DarkFg }
            }
            
            $logTextBox.AppendText("$FullMessage`r`n")
            $logTextBox.SelectionColor = $DarkFg
            $logTextBox.ScrollToCaret()
        })
    }
}

function Show-ConfirmDialog {
    param([string]$Title, [string]$Message)
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

function Show-InfoDialog {
    param([string]$Title, [string]$Message)
    
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-ErrorDialog {
    param([string]$Title, [string]$Message)
    
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

#endregion

#region Core Functions - App Removal
function Remove-AppxPackageByName {
    param([string]$AppName)
    
    try {
        # Current user
        $CurrentUserApps = Get-AppxPackage -Name $AppName -ErrorAction SilentlyContinue
        if ($CurrentUserApps) {
            $CurrentUserApps | Remove-AppxPackage -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Provisioned
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | 
            Where-Object DisplayName -Like $AppName | 
            Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
        
        Add-LogMessage "Removed app: $AppName" 'SUCCESS'
        $Script:AppsRemoved++
        return $true
    } catch {
        Add-LogMessage "Failed to remove $AppName : $($_.Exception.Message)" 'ERROR'
        $Script:ErrorCount++
        return $false
    }
}

#endregion

#region Core Functions - Services
function Set-ServiceState {
    param([string]$ServiceName, [string]$State)
    
    try {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $Service) {
            Add-LogMessage "Service not found: $ServiceName" 'WARN'
            return $false
        }
        
        # Convert state names
        $StateMap = @{
            'Auto'     = 'Automatic'
            'Manual'   = 'Manual'
            'Disabled' = 'Disabled'
        }
        
        $DesiredState = $StateMap[$State]
        Set-Service -Name $ServiceName -StartupType $DesiredState -ErrorAction SilentlyContinue | Out-Null
        
        # Stop if disabling
        if ($State -eq 'Disabled') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue | Out-Null
        }
        
        Add-LogMessage "Service '$ServiceName' set to $State" 'SUCCESS'
        $Script:ServicesModified++
        return $true
    } catch {
        Add-LogMessage "Error setting service $ServiceName : $($_.Exception.Message)" 'ERROR'
        $Script:ErrorCount++
        return $false
    }
}

#endregion

#region Core Functions - Registry
function Set-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWORD')
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
        }
        
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction SilentlyContinue | Out-Null
        
        Add-LogMessage "Registry: $Path\$Name = $Value" 'SUCCESS'
        $Script:RegistryChanges++
        return $true
    } catch {
        Add-LogMessage "Registry error at $Path : $($_.Exception.Message)" 'ERROR'
        $Script:ErrorCount++
        return $false
    }
}

#endregion

#region Preset Modes
function Invoke-PerformanceMode {
    param([System.Windows.Forms.ProgressBar]$ProgressBar)
    
    if (-not (Show-ConfirmDialog 'Confirm', 'Apply Performance Mode (balanced debloat)?')) {
        Add-LogMessage 'Operation cancelled by user' 'INFO'
        return
    }
    
Add-LogMessage '--- PERFORMANCE MODE ---' 'INFO'
    Add-LogMessage 'Removing bloatware...' 'INFO'
    
    # Apps to remove
    @(
        '*Microsoft.BingWeather*'
        '*Microsoft.BingNews*'
        '*Microsoft.BingFinance*'
        '*Clipchamp.Clipchamp*'
        '*Microsoft.GetHelp*'
        '*Microsoft.Getstarted*'
        '*Microsoft.MicrosoftOfficeHub*'
        '*Microsoft.MicrosoftSolitaireCollection*'
        '*Microsoft.YourPhone*'
        '*Microsoft.SkypeApp*'
        '*Microsoft.Xbox*'
        '*Microsoft.XboxApp*'
        '*Microsoft.XboxGameOverlay*'
        '*Microsoft.XboxGamingOverlay*'
        '*MicrosoftWindows.Client.WebExperience*'
    ) | ForEach-Object {
        Remove-AppxPackageByName $_
        $ProgressBar.Value += 1
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    Add-LogMessage 'Disabling services...' 'INFO'
    
    # Services
    @(
        @{ Name='DiagTrack'; State='Disabled' }
        @{ Name='dmwappushservice'; State='Disabled' }
        @{ Name='SysMain'; State='Manual' }
        @{ Name='WaaSMedicSvc'; State='Disabled' }
    ) | ForEach-Object {
        Set-ServiceState $_.Name $_.State
        $ProgressBar.Value += 1
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    Add-LogMessage 'Applying registry tweaks...' 'INFO'
    
    # Telemetry
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 'DWORD'
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Advertising' 'DisabledForUser' 1 'DWORD'
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 'DWORD'
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryManagerEnabled' 0 'DWORD'
    
    $ProgressBar.Value = 100
    Add-LogMessage 'Performance Mode completed!' 'SUCCESS'
}

function Invoke-PotatoMode {
    param([System.Windows.Forms.ProgressBar]$ProgressBar)
    
    if (-not (Show-ConfirmDialog 'WARNING', 'Potato Mode is VERY aggressive - may break some features. Continue?')) {
        Add-LogMessage 'Operation cancelled by user' 'INFO'
        return
    }
    
Add-LogMessage '--- POTATO PC MODE ---' 'INFO'
    
    # First apply Performance mode as base
    $tempProgress = $ProgressBar
    $tempProgress.Maximum = 100
    
    # Apps to remove (including Edge, Store)
    @(
        '*Microsoft.BingWeather*'
        '*Microsoft.BingNews*'
        '*Microsoft.WindowsStore*'
        '*Microsoft.MicrosoftEdge*'
        '*Microsoft.Xbox*'
        '*Microsoft.XboxApp*'
        '*Microsoft.YourPhone*'
        '*Microsoft.ZuneMusic*'
        '*Microsoft.ZuneVideo*'
        '*Microsoft.OneConnect*'
        '*Microsoft.Todos*'
        '*MicrosoftWindows.Client.WebExperience*'
    ) | ForEach-Object {
        Remove-AppxPackageByName $_
        $ProgressBar.Value += 1
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    # Aggressive services
    @(
        @{ Name='DiagTrack'; State='Disabled' }
        @{ Name='dmwappushservice'; State='Disabled' }
        @{ Name='SysMain'; State='Disabled' }
        @{ Name='WSearch'; State='Disabled' }
        @{ Name='Spooler'; State='Disabled' }
        @{ Name='WaaSMedicSvc'; State='Disabled' }
        @{ Name='WMPNetworkSvc'; State='Disabled' }
    ) | ForEach-Object {
        Set-ServiceState $_.Name $_.State
        $ProgressBar.Value += 1
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    # OneDrive removal
    Add-LogMessage 'Removing OneDrive...' 'INFO'
    try {
        Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $Uninstaller = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
        if (Test-Path $Uninstaller) {
            & $Uninstaller /uninstall
            Start-Sleep -Seconds 2
        }
    } catch { }
    
    $ProgressBar.Value = 100
    Add-LogMessage 'Potato Mode completed! Recommend reboot.' 'SUCCESS'
}

function Invoke-UselessAppsMode {
    param([System.Windows.Forms.ProgressBar]$ProgressBar)
    
    if (-not (Show-ConfirmDialog 'Confirm', 'Remove only sponsored/junk apps (safe)?')) {
        Add-LogMessage 'Operation cancelled by user' 'INFO'
        return
    }
    
Add-LogMessage '--- USELESS APPS MODE ---' 'INFO'
    
    @(
        '*CandyCrush*'
        '*Disney*'
        '*Microsoft.MicrosoftSolitaireCollection*'
        '*Microsoft.BingNews*'
        '*Microsoft.BingWeather*'
        '*Spotify*'
        '*PandoraMediaInc*'
    ) | ForEach-Object {
        Remove-AppxPackageByName $_
        $ProgressBar.Value += 1
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    $ProgressBar.Value = 100
    Add-LogMessage 'Useless apps removed!' 'SUCCESS'
}

function Invoke-RevertMode {
    param([System.Windows.Forms.ProgressBar]$ProgressBar)
    
    if (-not (Show-ConfirmDialog 'Confirm', 'Restore default apps and services?')) {
        Add-LogMessage 'Operation cancelled by user' 'INFO'
        return
    }
    
Add-LogMessage '--- REVERT MODE ---' 'INFO'
    Add-LogMessage 'Restoring apps...' 'INFO'
    
    # Restore default apps
    @(
        'Microsoft.Paint'
        'Microsoft.WindowsCalculator'
        'Microsoft.WindowsNotepad'
        'Microsoft.WindowsAlarms'
        'Microsoft.Sticky'
        'Microsoft.Windows.Photos'
    ) | ForEach-Object {
        try {
            Get-AppxPackage -AllUsers -Name $_ -ErrorAction SilentlyContinue | 
                ForEach-Object {
                    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
                }
            Add-LogMessage "Restored: $_" 'SUCCESS'
        } catch { }
        $ProgressBar.Value += 10
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    Add-LogMessage 'Restoring services...' 'INFO'
    
    # Restore services
    @(
        @{ Name='DiagTrack'; State='Manual' }
        @{ Name='dmwappushservice'; State='Manual' }
        @{ Name='SysMain'; State='Auto' }
        @{ Name='WSearch'; State='Auto' }
        @{ Name='Spooler'; State='Auto' }
    ) | ForEach-Object {
        Set-ServiceState $_.Name $_.State
        $ProgressBar.Value += 10
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    $ProgressBar.Value = 100
    Add-LogMessage 'Revert mode completed!' 'SUCCESS'
}

#endregion

#region Custom Mode
function Invoke-CustomMode {
    param(
        [string[]]$AppsToRemove,
        [hashtable[]]$ServicesToModify,
        [hashtable[]]$RegistryTweaks,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )
    
    if (-not (Show-ConfirmDialog 'Confirm', 'Apply custom selection?')) {
        Add-LogMessage 'Operation cancelled by user' 'INFO'
        return
    }
    
Add-LogMessage '--- CUSTOM MODE ---' 'INFO'
    
    # Apps
    if ($AppsToRemove.Count -gt 0) {
        Add-LogMessage "Removing $($AppsToRemove.Count) app(s)..." 'INFO'
        $AppsToRemove | ForEach-Object {
            Remove-AppxPackageByName $_
            $ProgressBar.Value += 1
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    
    # Services
    if ($ServicesToModify.Count -gt 0) {
        Add-LogMessage "Modifying $($ServicesToModify.Count) service(s)..." 'INFO'
        $ServicesToModify | ForEach-Object {
            Set-ServiceState $_.Name $_.State
            $ProgressBar.Value += 1
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    
    $ProgressBar.Value = 100
    Add-LogMessage 'Custom mode completed!' 'SUCCESS'
}

#endregion

#region GUI Creation
function Create-MainForm {
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    [System.Windows.Forms.Application]::EnableVisualStyles()
    
    # Define colors first as script variables to avoid scope issues
    $script:DarkBg = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $script:DarkFg = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $script:DarkAccent = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $script:DarkButton = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $script:DarkButtonFg = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $script:AccentBlue = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $script:WarningRed = [System.Drawing.Color]::FromArgb(220, 80, 80)
    $script:SuccessGreen = [System.Drawing.Color]::FromArgb(76, 175, 80)
    
    # Main form
    $form = New-Object System.Windows.Forms.Form
$form.Text = 'Adversity W11 Debloater GUI'
    $form.Width = 900
    $form.Height = 700
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = $DarkBg
    $form.ForeColor = $DarkFg
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $form.MinimumSize = New-Object System.Drawing.Size(800, 600)
    
    # Main layout panel
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = 'Fill'
    $mainPanel.BackColor = $DarkBg
    $mainPanel.Padding = '10, 10, 10, 10'
    
    #region Logo Label
    $logoLabel = New-Object System.Windows.Forms.Label
$logoLabel.Text = 'ADVERSITY W11 DEBLOATER v2.1 - Windows 11 Optimizer'
$logoLabel.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$logoLabel.ForeColor = $AccentBlue
    $logoLabel.BackColor = $DarkAccent
    $logoLabel.TextAlign = 'MiddleCenter'
    $logoLabel.AutoSize = $false
    $logoLabel.Height = 90
    $logoLabel.Dock = 'Top'
    $logoLabel.Margin = '0, 0, 0, 10'
    #endregion
    
    #region Tab Control
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = 'Fill'
    $tabControl.BackColor = $DarkBg
    $tabControl.ForeColor = $DarkFg
    $tabControl.Margin = '0, 0, 0, 10'
    
    #region Tab 1 - Home / Presets
    $tabHome = New-Object System.Windows.Forms.TabPage
    $tabHome.Text = 'Home / Presets'
    $tabHome.BackColor = $DarkBg
    $tabHome.ForeColor = $DarkFg
    
    $homePanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $homePanel.Dock = 'Fill'
    $homePanel.BackColor = $DarkBg
    $homePanel.FlowDirection = 'TopDown'
    $homePanel.Padding = '10, 10, 10, 10'
    
    # Info label
    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = 'Select a preset mode or use Custom Tweaks for granular control:'
    $infoLabel.ForeColor = $DarkFg
    $infoLabel.BackColor = $DarkBg
    $infoLabel.AutoSize = $true
    $infoLabel.Margin = '0, 0, 0, 15'
    $homePanel.Controls.Add($infoLabel)
    
    # Performance Mode Button
$btnPerformance = New-Object System.Windows.Forms.Button
$btnPerformance.Text = 'PERFORMANCE MODE'
    $btnPerformance.Width = 300
    $btnPerformance.Height = 80
    $btnPerformance.BackColor = $AccentBlue
    $btnPerformance.ForeColor = 'White'
    $btnPerformance.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $btnPerformance.FlatStyle = 'Flat'
    $btnPerformance.Margin = '0, 10, 0, 10'
    $btnPerformance.ToolTip = New-Object System.Windows.Forms.ToolTip
    $btnPerformance.ToolTip.SetToolTip($btnPerformance, 'Balanced debloat: removes bloatware, telemetry services, privacy tweaks. Recommended for most users.')
    $homePanel.Controls.Add($btnPerformance)
    
    $lblPerformance = New-Object System.Windows.Forms.Label
    $lblPerformance.Text = "Balanced debloat + privacy tweaks`nRemoves bloatware, keeps essentials`n(Recommended for most users)"
$lblPerformance.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$lblPerformance.BackColor = $DarkAccent
    $lblPerformance.AutoSize = $true
    $lblPerformance.Margin = '10, 0, 0, 15'
    $homePanel.Controls.Add($lblPerformance)
    
    # Potato Mode Button
$btnPotato = New-Object System.Windows.Forms.Button
$btnPotato.Text = 'POTATO PC MODE'
    $btnPotato.Width = 300
    $btnPotato.Height = 80
    $btnPotato.BackColor = $WarningRed
    $btnPotato.ForeColor = 'White'
    $btnPotato.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $btnPotato.FlatStyle = 'Flat'
    $btnPotato.Margin = '0, 10, 0, 10'
    $btnPotato.ToolTip = New-Object System.Windows.Forms.ToolTip
    $btnPotato.ToolTip.SetToolTip($btnPotato, 'Ultra aggressive for old hardware: removes Edge, Store, OneDrive, most services. WARNING: May break features.')
    $homePanel.Controls.Add($btnPotato)
    
    $lblPotato = New-Object System.Windows.Forms.Label
    $lblPotato.Text = "Ultra-aggressive for old hardware`nRemoves Edge, Store, OneDrive, most services`n(WARNING: May break some features)"
$lblPotato.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 200)
$lblPotato.BackColor = $DarkAccent
    $lblPotato.AutoSize = $true
    $lblPotato.Margin = '10, 0, 0, 15'
    $homePanel.Controls.Add($lblPotato)
    
    # Useless Apps Button
$btnUseless = New-Object System.Windows.Forms.Button
$btnUseless.Text = 'USELESS APPS ONLY'
    $btnUseless.Width = 300
    $btnUseless.Height = 80
    $btnUseless.BackColor = $SuccessGreen
    $btnUseless.ForeColor = 'White'
    $btnUseless.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $btnUseless.FlatStyle = 'Flat'
    $btnUseless.Margin = '0, 10, 0, 10'
    $btnUseless.ToolTip = New-Object System.Windows.Forms.ToolTip
    $btnUseless.ToolTip.SetToolTip($btnUseless, 'Safe removal of sponsored/junk apps only: Candy Crush, News, Weather, etc.')
    $homePanel.Controls.Add($btnUseless)
    
    $lblUseless = New-Object System.Windows.Forms.Label
    $lblUseless.Text = "Remove only sponsored/junk apps`nCandy Crush, News, Weather, etc.`n(Safe and minimal - very reversible)"
$lblUseless.ForeColor = [System.Drawing.Color]::FromArgb(200, 255, 200)
$lblUseless.BackColor = $DarkAccent
    $lblUseless.AutoSize = $true
    $lblUseless.Margin = '10, 0, 0, 15'
    $homePanel.Controls.Add($lblUseless)
    
    # Revert Button
    $btnRevert = New-Object System.Windows.Forms.Button
$btnRevert.Text = 'REVERT CHANGES'
    $btnRevert.Width = 300
    $btnRevert.Height = 60
    $btnRevert.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnRevert.ForeColor = 'White'
    $btnRevert.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btnRevert.FlatStyle = 'Flat'
    $btnRevert.Margin = '0, 10, 0, 10'
    $homePanel.Controls.Add($btnRevert)
    
    $tabHome.Controls.Add($homePanel)
    $tabControl.TabPages.Add($tabHome)
    #endregion
    
    #region Tab 2 - Custom Tweaks
    $tabCustom = New-Object System.Windows.Forms.TabPage
    $tabCustom.Text = 'Custom Tweaks'
    $tabCustom.BackColor = $DarkBg
    $tabCustom.ForeColor = $DarkFg
    
$customPanel = New-Object System.Windows.Forms.Panel
    $customPanel.Dock = 'Fill'
    $customPanel.BackColor = $DarkBg
    $customPanel.AutoScroll = $true
    $customPanel.Padding = '10, 10, 10, 10'
    
    $grpApps.Top = 0
    
    # Apps group
$grpApps = New-Object System.Windows.Forms.GroupBox
    $grpApps.Text = 'Applications to Remove'
    $grpApps.ToolTip = New-Object System.Windows.Forms.ToolTip
    $grpApps.ToolTip.SetToolTip($grpApps, 'Select apps to remove from your system. Safe to remove these.')
    $grpApps.BackColor = $DarkAccent
    $grpApps.ForeColor = $DarkFg
    $grpApps.Dock = 'Top'
    $grpApps.Height = 160
    $grpApps.Margin = '5, 5, 5, 10'
    
    $flowApps = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowApps.Dock = 'Fill'
    $flowApps.BackColor = $DarkAccent
    $flowApps.FlowDirection = 'TopDown'
    $flowApps.AutoScroll = $true
    
    $CommonApps | ForEach-Object {
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = $_.Display
        $chk.BackColor = $DarkAccent
        $chk.ForeColor = $DarkFg
        $chk.Tag = $_.Name
        $chk.AutoSize = $true
        $chk.Margin = '5, 2, 5, 2'
        $flowApps.Controls.Add($chk)
    }
    
    $grpApps.Controls.Add($flowApps)
    $customPanel.Controls.Add($grpApps)
    
    # Services group
$grpServices = New-Object System.Windows.Forms.GroupBox
    $grpServices.Text = 'Services to Modify'
    $grpServices.ToolTip = New-Object System.Windows.Forms.ToolTip
    $grpServices.ToolTip.SetToolTip($grpServices, 'Select services to disable. These will be set to Disabled and stopped.')
    $grpServices.BackColor = $DarkAccent
    $grpServices.ForeColor = $DarkFg
    $grpServices.Dock = 'Top'
    $grpServices.Height = 160
    $grpServices.Margin = '5, 5, 5, 10'
    
    $flowServices = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowServices.Dock = 'Fill'
    $flowServices.BackColor = $DarkAccent
    $flowServices.FlowDirection = 'TopDown'
    $flowServices.AutoScroll = $true
    
    $serviceCheckboxes = @()
    $ServicesList | ForEach-Object {
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = "$($_.Display) (→ Disabled)"
        $chk.BackColor = $DarkAccent
        $chk.ForeColor = $DarkFg
        $chk.Tag = @{ Name=$_.Name; State='Disabled' }
        $chk.AutoSize = $true
        $chk.Margin = '5, 2, 5, 2'
        $flowServices.Controls.Add($chk)
        $serviceCheckboxes += $chk
    }
    
    $grpServices.Controls.Add($flowServices)
    $customPanel.Controls.Add($grpServices)
    
    # Buttons panel
    $btnPanel = New-Object System.Windows.Forms.Panel
    $btnPanel.BackColor = $DarkBg
    $btnPanel.Height = 45
    $btnPanel.Dock = 'Bottom'
    $btnPanel.Padding = '5, 5, 5, 5'
    
    $btnApplyCustom = New-Object System.Windows.Forms.Button
    $btnApplyCustom.Text = 'APPLY CUSTOM TWEAKS'
    $btnApplyCustom.Width = 200
    $btnApplyCustom.Height = 35
    $btnApplyCustom.BackColor = $AccentBlue
    $btnApplyCustom.ForeColor = 'White'
    $btnApplyCustom.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btnApplyCustom.FlatStyle = 'Flat'
    $btnApplyCustom.Left = 10
    $btnPanel.Controls.Add($btnApplyCustom)
    
    $customPanel.Controls.Add($btnPanel)
    $tabCustom.Controls.Add($customPanel)
    $tabControl.TabPages.Add($tabCustom)
    #endregion
    
    #region Tab 3 - About / Logs
    $tabAbout = New-Object System.Windows.Forms.TabPage
    $tabAbout.Text = 'Logs'
    $tabAbout.BackColor = $DarkBg
    $tabAbout.ForeColor = $DarkFg
    
    $aboutPanel = New-Object System.Windows.Forms.Panel
    $aboutPanel.Dock = 'Fill'
    $aboutPanel.BackColor = $DarkBg
    $aboutPanel.Padding = '10, 10, 10, 10'
    
    $logTextBox = New-Object System.Windows.Forms.RichTextBox
    $logTextBox.Dock = 'Fill'
    $logTextBox.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 15)
    $logTextBox.ForeColor = [System.Drawing.Color]::LimeGreen
    $logTextBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $logTextBox.ReadOnly = $true
    
    $aboutPanel.Controls.Add($logTextBox)
    $tabAbout.Controls.Add($aboutPanel)
    $tabControl.TabPages.Add($tabAbout)
    #endregion
    
    $mainPanel.Controls.Add($logoLabel)
    $mainPanel.Controls.Add($tabControl)
    $form.Controls.Add($mainPanel)
    
    #region Progress Bar & Status Bar
    $progressPanel = New-Object System.Windows.Forms.Panel
    $progressPanel.Height = 50
    $progressPanel.Dock = 'Bottom'
    $progressPanel.BackColor = $DarkAccent
    $progressPanel.Padding = '10, 5, 10, 5'
    
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Width = 800
    $progressBar.Height = 20
    $progressBar.Left = 10
    $progressBar.Top = 5
    $progressBar.Maximum = 100
    $progressBar.Style = 'Continuous'
    $progressPanel.Controls.Add($progressBar)
    
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = 'Ready'
    $statusLabel.ForeColor = $SuccessGreen
    $statusLabel.BackColor = $DarkAccent
    $statusLabel.Left = 10
    $statusLabel.Top = 28
    $statusLabel.AutoSize = $true
    $progressPanel.Controls.Add($statusLabel)
    
    $form.Controls.Add($progressPanel)
    #endregion
    
    #region Button Events
    $btnPerformance.Add_Click({
        if ($Script:IsProcessing) { return }
        $Script:IsProcessing = $true
        $statusLabel.Text = 'Running Performance Mode...'
        $statusLabel.ForeColor = [System.Drawing.Color]::Yellow
        $progressBar.Value = 0
        $progressBar.Maximum = 20
        
        try {
            Invoke-PerformanceMode $progressBar
            $statusLabel.Text = 'Completed! Consider rebooting.'
            $statusLabel.ForeColor = $SuccessGreen
        } catch {
            $statusLabel.Text = "Error: $($_.Exception.Message)"
            $statusLabel.ForeColor = $WarningRed
            Add-LogMessage "Exception: $($_.Exception.Message)" 'ERROR'
        } finally {
            $Script:IsProcessing = $false
        }
    })
    
    $btnPotato.Add_Click({
        if ($Script:IsProcessing) { return }
        $Script:IsProcessing = $true
        $statusLabel.Text = 'Running Potato Mode...'
        $statusLabel.ForeColor = [System.Drawing.Color]::Yellow
        $progressBar.Value = 0
        $progressBar.Maximum = 30
        
        try {
            Invoke-PotatoMode $progressBar
            $statusLabel.Text = 'Completed! YOU MUST REBOOT!'
            $statusLabel.ForeColor = $WarningRed
        } catch {
            $statusLabel.Text = "Error: $($_.Exception.Message)"
            $statusLabel.ForeColor = $WarningRed
            Add-LogMessage "Exception: $($_.Exception.Message)" 'ERROR'
        } finally {
            $Script:IsProcessing = $false
        }
    })
    
    $btnUseless.Add_Click({
        if ($Script:IsProcessing) { return }
        $Script:IsProcessing = $true
        $statusLabel.Text = 'Running Useless Apps Mode...'
        $statusLabel.ForeColor = [System.Drawing.Color]::Yellow
        $progressBar.Value = 0
        $progressBar.Maximum = 10
        
        try {
            Invoke-UselessAppsMode $progressBar
            $statusLabel.Text = 'Completed!'
            $statusLabel.ForeColor = $SuccessGreen
        } catch {
            $statusLabel.Text = "Error: $($_.Exception.Message)"
            $statusLabel.ForeColor = $WarningRed
            Add-LogMessage "Exception: $($_.Exception.Message)" 'ERROR'
        } finally {
            $Script:IsProcessing = $false
        }
    })
    
    $btnRevert.Add_Click({
        if ($Script:IsProcessing) { return }
        $Script:IsProcessing = $true
        $statusLabel.Text = 'Running Revert Mode...'
        $statusLabel.ForeColor = [System.Drawing.Color]::Yellow
        $progressBar.Value = 0
        $progressBar.Maximum = 50
        
        try {
            Invoke-RevertMode $progressBar
            $statusLabel.Text = 'Reverted settings. Some changes may be permanent.'
            $statusLabel.ForeColor = $SuccessGreen
        } catch {
            $statusLabel.Text = "Error: $($_.Exception.Message)"
            $statusLabel.ForeColor = $WarningRed
            Add-LogMessage "Exception: $($_.Exception.Message)" 'ERROR'
        } finally {
            $Script:IsProcessing = $false
        }
    })
    
    $btnApplyCustom.Add_Click({
        if ($Script:IsProcessing) { return }
        
        # Collect selected items
        $appsToRemove = @()
        $flowApps.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] -and $_.Checked } | 
            ForEach-Object { $appsToRemove += $_.Tag }
        
        $servicesToModify = @()
        $flowServices.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] -and $_.Checked } | 
            ForEach-Object { $servicesToModify += @{ Name=$_.Tag.Name; State=$_.Tag.State } }
        
        if ($appsToRemove.Count -eq 0 -and $servicesToModify.Count -eq 0) {
            Show-InfoDialog 'Selection', 'Please select at least one item.'
            return
        }
        
        $Script:IsProcessing = $true
        $statusLabel.Text = 'Running Custom Mode...'
        $statusLabel.ForeColor = [System.Drawing.Color]::Yellow
        $progressBar.Value = 0
        $progressBar.Maximum = ($appsToRemove.Count + $servicesToModify.Count)
        
        try {
            Invoke-CustomMode -AppsToRemove $appsToRemove -ServicesToModify $servicesToModify -ProgressBar $progressBar
            $statusLabel.Text = 'Custom tweaks applied!'
            $statusLabel.ForeColor = $SuccessGreen
        } catch {
            $statusLabel.Text = "Error: $($_.Exception.Message)"
            $statusLabel.ForeColor = $WarningRed
            Add-LogMessage "Exception: $($_.Exception.Message)" 'ERROR'
        } finally {
            $Script:IsProcessing = $false
        }
    })
    
    $form.Add_FormClosed({
        $Script:WindowOpen = $false
        
        # Show summary
        $summary = @"
========================================
EXECUTION SUMMARY
========================================
Apps Removed:       $($Script:AppsRemoved)
Services Modified:  $($Script:ServicesModified)
Registry Changes:   $($Script:RegistryChanges)
Errors:             $($Script:ErrorCount)
========================================

Log file saved to: $env:TEMP\Adversity-W11-$(Get-Date -Format 'yyyyMMdd-HHmmss').log
"@
        
$Script:LogMessages | Out-File -FilePath "$env:TEMP\Adversity-W11-$(Get-Date -Format 'yyyyMMdd-HHmmss').log" -Encoding UTF8
        
        Show-InfoDialog 'Session Complete', $summary
    })
    
    #endregion
    
    return $form
}

#endregion

#region Main Entry Point
# Check admin privileges
if (-not (Test-AdminPrivileges)) {
    Request-AdminPrivileges
}

# Create and show GUI
Add-LogMessage 'Adversity W11 Debloater GUI Starting...' 'INFO'
$form = Create-MainForm

# Splash delay inside form - removed external reference to avoid scope error
# (handled by form load event or timer if needed)

$form.ShowDialog() | Out-Null

Add-LogMessage 'Adversity W11 Debloater GUI Closed' 'INFO'
exit
#endregion
