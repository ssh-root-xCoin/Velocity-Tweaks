<#
    Velocity - Windows Performance Toolkit
    -------------------------------------------------------------------------
    A safe, transparent, reversible Windows tuning tool.

    Design philosophy (see DESIGN.md):
      - Every value references a token. Colors, type sizes, radii, spacing and
        motion are defined ONCE as resources and reused everywhere.
      - Every control does something real. No decorative buttons.
      - Every tweak is reversible and reports its true current state.
      - The tool diagnoses before it changes anything. It refuses to ship the
        snake-oil and security holes common to "FPS booster" packs.

    Run via Velocity.bat (auto-elevates). Requires Windows 10/11 + PowerShell 5.1.
#>
param([switch]$Test)

$ErrorActionPreference = 'Stop'

# --- Elevation --------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin -and -not $Test) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms | Out-Null

# ============================================================================
#  REGISTRY / SYSTEM HELPERS
# ============================================================================
function ConvertTo-PsPath([string]$p) {
    ($p -replace '^HKLM\\', 'HKLM:\') -replace '^HKCU\\', 'HKCU:\'
}
function Set-RegDword([string]$Path, [string]$Name, [long]$Value) {
    & reg.exe add $Path /v $Name /t REG_DWORD /d $Value /f *> $null
}
function Set-RegSz([string]$Path, [string]$Name, [string]$Value) {
    & reg.exe add $Path /v $Name /t REG_SZ /d $Value /f *> $null
}
function Remove-RegValue([string]$Path, [string]$Name) {
    & reg.exe delete $Path /v $Name /f *> $null
}
function Get-RegValue([string]$Path, [string]$Name) {
    $ps = ConvertTo-PsPath $Path
    try { (Get-ItemProperty -LiteralPath $ps -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

# ============================================================================
#  TWEAK CATALOG  (data-driven; UI is generated from this)
#  Type:  'Toggle' = on/off state with Apply/Revert/Test
#         'Action' = one-shot operation (Run)
#  Risk:  'Safe' (proven, low-impact, reversible) | 'Caution' (changes a
#         subsystem like networking) | 'Security' (restores a protection)
# ============================================================================
$Tweaks = @(
    # ---------------- PERFORMANCE ----------------
    [pscustomobject]@{ Id='hags'; Cat='Performance'; Type='Toggle'; Risk='Safe'; Reboot=$true
        Name='Hardware-Accelerated GPU Scheduling'
        Desc='Lets the GPU manage its own memory/scheduling. Reduces latency on modern NVIDIA, AMD and Intel GPUs. Requires a reboot.'
        Apply={ Set-RegDword 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
        Revert={ Set-RegDword 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1 }
        Test={ (Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode') -eq 2 } }

    [pscustomobject]@{ Id='gamedvr'; Cat='Performance'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Disable Game DVR / Background Recording'
        Desc='Stops the always-on Xbox capture pipeline. A real, measurable FPS gain in many titles. Game Bar overlay still works.'
        Apply={ Set-RegDword 'HKCU\System\GameConfigStore' 'GameDVR_Enabled' 0
                Set-RegDword 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
                Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 }
        Revert={ Set-RegDword 'HKCU\System\GameConfigStore' 'GameDVR_Enabled' 1
                 Remove-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'
                 Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1 }
        Test={ (Get-RegValue 'HKCU\System\GameConfigStore' 'GameDVR_Enabled') -eq 0 } }

    [pscustomobject]@{ Id='prio'; Cat='Performance'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Foreground Priority Boost'
        Desc='Sets Win32PrioritySeparation so the focused app (your game) gets longer, more frequent CPU time slices.'
        Apply={ Set-RegDword 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38 }
        Revert={ Set-RegDword 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 2 }
        Test={ (Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation') -eq 38 } }

    [pscustomobject]@{ Id='powerthrottle'; Cat='Performance'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Disable CPU Power Throttling'
        Desc='Prevents Windows from down-clocking background-eligible threads. Sensible on a desktop that is always plugged in.'
        HwWarn='On a laptop or a system with weak cooling this raises heat and power draw and can cause thermal throttling or shorter battery life. Best on a well-cooled, plugged-in desktop.'
        Apply={ Set-RegDword 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
        Revert={ Remove-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' }
        Test={ (Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff') -eq 1 } }

    [pscustomobject]@{ Id='mmcss'; Cat='Performance'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Multimedia Scheduler Priority (Games)'
        Desc='Tunes MMCSS so games get high GPU/CPU scheduling priority and the OS reserves less CPU for low-priority work.'
        Apply={ Set-RegDword 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10
                Set-RegDword 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 8
                Set-RegDword 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6
                Set-RegSz   'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' }
        Revert={ Set-RegDword 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 20
                 Set-RegSz   'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'Medium' }
        Test={ [int](Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness') -le 10 } }

    [pscustomobject]@{ Id='faststartup'; Cat='Performance'; Type='Toggle'; Risk='Caution'; Reboot=$true
        Name='Disable Fast Startup'
        Desc='Turns off hybrid shutdown (a hidden hibernation). A frequent cause of black screens on boot, multi-display init glitches and drivers not reloading cleanly. Makes a real "cold" shutdown each time.'
        Apply={ Set-RegDword 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 }
        Revert={ Set-RegDword 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1 }
        Test={ (Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled') -eq 0 } }

    [pscustomobject]@{ Id='mpo'; Cat='Performance'; Type='Toggle'; Risk='Caution'; Reboot=$true
        Name='Disable Multi-Plane Overlay (MPO)'
        Desc='Disables the DWM overlay feature behind a well-known flickering / random black-screen bug on multi-monitor and mixed-refresh setups. The standard NVIDIA/Microsoft workaround. Reverts by removing the key.'
        Apply={ Set-RegDword 'HKLM\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5 }
        Revert={ Remove-RegValue 'HKLM\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' }
        Test={ (Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode') -eq 5 } }

    [pscustomobject]@{ Id='ultimateplan'; Cat='Performance'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Ultimate Performance Power Plan'
        Desc='Activates Windows'' hidden "Ultimate Performance" plan: removes micro-latency from power-state switching. Best on a desktop. Revert returns you to Balanced.'
        HwWarn='This plan keeps clocks and fans high and disables power saving. On a laptop or a thermally-limited PC it means more heat and much shorter battery life. Ideal only on a well-cooled, plugged-in desktop.'
        Apply={ $g='e9a42b02-d5df-448d-aa00-03f14749eb61'; cmd /c "powercfg -duplicatescheme $g" 2>$null | Out-Null; cmd /c "powercfg -setactive $g" 2>$null | Out-Null }
        Revert={ cmd /c "powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e" 2>$null | Out-Null }
        Test={ (cmd /c "powercfg -getactivescheme") -match 'Ultimate Performance' } }

    # ---------------- LATENCY & INPUT ----------------
    [pscustomobject]@{ Id='mouseaccel'; Cat='Latency & Input'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Disable Mouse Acceleration'
        Desc='Turns off "Enhance pointer precision" so cursor distance maps 1:1 to mouse movement. Essential for aim consistency.'
        Apply={ Set-RegSz 'HKCU\Control Panel\Mouse' 'MouseSpeed' '0'
                Set-RegSz 'HKCU\Control Panel\Mouse' 'MouseThreshold1' '0'
                Set-RegSz 'HKCU\Control Panel\Mouse' 'MouseThreshold2' '0' }
        Revert={ Set-RegSz 'HKCU\Control Panel\Mouse' 'MouseSpeed' '1'
                 Set-RegSz 'HKCU\Control Panel\Mouse' 'MouseThreshold1' '6'
                 Set-RegSz 'HKCU\Control Panel\Mouse' 'MouseThreshold2' '10' }
        Test={ (Get-RegValue 'HKCU\Control Panel\Mouse' 'MouseSpeed') -eq '0' } }

    [pscustomobject]@{ Id='menudelay'; Cat='Latency & Input'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Instant Menu Response'
        Desc='Removes the 400ms delay before menus open. Makes the whole desktop feel immediate. Purely cosmetic timing.'
        Apply={ Set-RegSz 'HKCU\Control Panel\Desktop' 'MenuShowDelay' '0' }
        Revert={ Set-RegSz 'HKCU\Control Panel\Desktop' 'MenuShowDelay' '400' }
        Test={ (Get-RegValue 'HKCU\Control Panel\Desktop' 'MenuShowDelay') -eq '0' } }

    [pscustomobject]@{ Id='startupdelay'; Cat='Latency & Input'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Remove Startup App Delay'
        Desc='Skips the artificial ~10s delay Windows adds before launching your startup apps after sign-in.'
        Apply={ Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0 }
        Revert={ Remove-RegValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' }
        Test={ (Get-RegValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec') -eq 0 } }

    # ---------------- NETWORK ----------------
    [pscustomobject]@{ Id='netthrottle'; Cat='Network'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Disable Network Throttling'
        Desc='Lifts the multimedia network throttle (10 packets/ms). Helps high-rate online games. Safe on modern hardware.'
        Apply={ Set-RegDword 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 4294967295 }
        Revert={ Set-RegDword 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 10 }
        Test={ $v=Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'; $v -eq -1 -or $v -eq 4294967295 } }

    [pscustomobject]@{ Id='nagle'; Cat='Network'; Type='Toggle'; Risk='Caution'; Reboot=$false
        Name="Disable Nagle's Algorithm"
        Desc='Stops batching of small TCP packets on your active adapters. Lowers latency for twitch games; can slightly raise overhead on slow links.'
        Apply={ foreach ($k in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces')) {
                    $p = $k.PSChildName
                    $ip = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue)
                    if ($ip.DhcpIPAddress -or $ip.IPAddress) {
                        Set-RegDword "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$p" 'TcpAckFrequency' 1
                        Set-RegDword "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$p" 'TCPNoDelay' 1 } } }
        Revert={ foreach ($k in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces')) {
                    $p = $k.PSChildName
                    Remove-RegValue "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$p" 'TcpAckFrequency'
                    Remove-RegValue "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$p" 'TCPNoDelay' } }
        Test={ $hit=$false; foreach ($k in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces')) {
                    if ((Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).TcpAckFrequency -eq 1) { $hit=$true } }; $hit } }

    # ---------------- PRIVACY & TELEMETRY ----------------
    [pscustomobject]@{ Id='telemetry'; Cat='Privacy & Telemetry'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Minimize Telemetry'
        Desc='Sets the diagnostic data level to the lowest the OS allows. Does not touch security definitions or Defender.'
        Apply={ Set-RegDword 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
                Set-RegDword 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0 }
        Revert={ Set-RegDword 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1
                 Remove-RegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' }
        Test={ (Get-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry') -eq 0 } }

    [pscustomobject]@{ Id='adid'; Cat='Privacy & Telemetry'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Disable Advertising ID'
        Desc='Stops apps from using a per-user ad identifier to profile you across the system.'
        Apply={ Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 }
        Revert={ Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 1 }
        Test={ (Get-RegValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled') -eq 0 } }

    [pscustomobject]@{ Id='suggested'; Cat='Privacy & Telemetry'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Disable Suggested Content & Tips'
        Desc='Removes Start-menu suggestions, Settings ads and the "tips" notifications that quietly phone home.'
        Apply={ foreach ($n in 'SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353698Enabled','SystemPaneSuggestionsEnabled','SoftLandingEnabled') {
                    Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $n 0 } }
        Revert={ foreach ($n in 'SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353698Enabled','SystemPaneSuggestionsEnabled','SoftLandingEnabled') {
                    Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $n 1 } }
        Test={ (Get-RegValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled') -eq 0 } }

    [pscustomobject]@{ Id='bingsearch'; Cat='Privacy & Telemetry'; Type='Toggle'; Risk='Safe'; Reboot=$false
        Name='Disable Web Search in Start Menu'
        Desc='Keeps Start search local instead of sending every keystroke to Bing. Also makes search noticeably faster.'
        Apply={ Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
                Set-RegDword 'HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 }
        Revert={ Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 1
                 Remove-RegValue 'HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' }
        Test={ (Get-RegValue 'HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions') -eq 1 } }

    # ---------------- SECURITY (restores protections common packs disable) ----------------
    [pscustomobject]@{ Id='smartscreen'; Cat='Security'; Type='Toggle'; Risk='Security'; Reboot=$false
        Name='SmartScreen (Reputation Protection)'
        Desc='Warns before running unrecognized downloads. Many "tweak" packs silently disable this. ON is the safe default.'
        Apply={ Set-RegSz   'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled' 'Warn'
                Set-RegDword 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' 1
                Set-RegDword 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost' 'EnableWebContentEvaluation' 1 }
        Revert={ Set-RegSz 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled' 'Off'
                 Set-RegDword 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' 0 }
        Test={ $v=Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled'; $v -and $v -ne 'Off' } }

    [pscustomobject]@{ Id='timesync'; Cat='Security'; Type='Action'; Risk='Security'; Reboot=$false
        Name='Repair Windows Time Sync'
        Desc='Re-enables the time service and resyncs the clock. A wrong clock breaks HTTPS, logins and anti-cheat. Packs often disable this.'
        Run={ & sc.exe config W32Time start= demand *> $null
              & net.exe start W32Time *> $null
              foreach ($t in 'SynchronizeTime','ForceSynchronizeTime') { & schtasks.exe /change /tn "\Microsoft\Windows\Time Synchronization\$t" /enable *> $null }
              & w32tm.exe /resync /force *> $null
              return 'Time service re-enabled and clock resynced.' } }

    # ---------------- CLEANUP ----------------
    [pscustomobject]@{ Id='temp'; Cat='Cleanup'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Clear Temporary Files'
        Desc='Deletes user + Windows temp files. (Deliberately does NOT touch Prefetch - clearing it slows your next boots.)'
        Run={ $before=0; $paths=@($env:TEMP, "$env:SystemRoot\Temp")
              foreach ($p in $paths) { if (Test-Path $p) { $before += (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
                  Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
              return ('Freed about {0:N0} MB of temp files.' -f ($before/1MB)) } }

    [pscustomobject]@{ Id='dns'; Cat='Cleanup'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Flush DNS Cache'
        Desc='Clears stale DNS entries. Fixes sites that load on your phone but not your PC.'
        Run={ & ipconfig.exe /flushdns *> $null; return 'DNS resolver cache flushed.' } }

    [pscustomobject]@{ Id='recyclebin'; Cat='Cleanup'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Empty Recycle Bin'
        Desc='Permanently removes deleted files across all drives.'
        Run={ Clear-RecycleBin -Force -ErrorAction SilentlyContinue; return 'Recycle Bin emptied.' } }

    # ---------------- DEBLOAT ----------------
    [pscustomobject]@{ Id='debloat'; Cat='Debloat'; Type='Action'; Risk='Caution'; Reboot=$false
        Name='Remove Common Bloatware Apps'
        Desc='Removes ad-ware Store apps (Bing News/Weather, Solitaire, Clipchamp, consumer Teams, etc.). Keeps media, Xbox & Game Bar. All reinstallable from the Store.'
        Run={ $targets='Microsoft.BingNews','Microsoft.BingWeather','Microsoft.MicrosoftSolitaireCollection','Microsoft.People','Microsoft.Getstarted','Microsoft.MicrosoftOfficeHub','Microsoft.Todos','Microsoft.PowerAutomateDesktop','Clipchamp.Clipchamp','MicrosoftTeams','Microsoft.windowscommunicationsapps','Microsoft.549981C3F5F10'
              $removed=0
              foreach ($t in $targets) { Get-AppxPackage -Name $t -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-AppxPackage $_ -ErrorAction Stop; $removed++ } catch {} } }
              return "$removed bloat app package(s) removed." } }

    # ---------------- SYSTEM & REPAIR ----------------
    [pscustomobject]@{ Id='restorepoint'; Cat='System & Repair'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Create System Restore Point'
        Desc='A full rollback safety net. Always do this before applying changes.'
        Run={ Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
              Set-RegDword 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
              Checkpoint-Computer -Description ('Velocity {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType 'MODIFY_SETTINGS'
              return 'Restore point created.' } }

    [pscustomobject]@{ Id='sfc'; Cat='System & Repair'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Repair System Files (SFC)'
        Desc='Scans and repairs corrupted Windows files. Opens in its own console so you can watch progress.'
        Run={ Start-Process powershell.exe -ArgumentList '-NoProfile -Command "sfc /scannow; Write-Host `n''Done. Press Enter.''; Read-Host"' -Verb RunAs; return 'SFC launched in a new window.' } }

    [pscustomobject]@{ Id='dism'; Cat='System & Repair'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Repair System Image (DISM)'
        Desc='Rebuilds the component store SFC relies on. Run this if SFC reports it could not fix everything.'
        Run={ Start-Process powershell.exe -ArgumentList '-NoProfile -Command "DISM /Online /Cleanup-Image /RestoreHealth; Write-Host `n''Done. Press Enter.''; Read-Host"' -Verb RunAs; return 'DISM launched in a new window.' } }

    [pscustomobject]@{ Id='winutil'; Cat='System & Repair'; Type='Action'; Risk='Safe'; Reboot=$false
        Name="Open WinUtil (Chris Titus Tech)"
        Desc='Launches the community-favourite open-source toolkit for installs, debloat and updates. Runs the official one-liner.'
        Run={ Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "irm https://christitus.com/win | iex"' -Verb RunAs; return 'WinUtil is launching in a new window.' } }

    [pscustomobject]@{ Id='startupapps'; Cat='System & Repair'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Manage Startup Apps'
        Desc='Opens the Startup apps manager so you can disable programs that launch at sign-in and slow your boot. Disabling here is fully reversible.'
        Run={ try { Start-Process 'ms-settings:startupapps' } catch { Start-Process taskmgr.exe '/0 /startup' }; return 'Startup apps manager opened.' } }

    [pscustomobject]@{ Id='optimizer'; Cat='System & Repair'; Type='Action'; Risk='Caution'; Reboot=$false
        Name='Get Optimizer (open-source, GitHub)'
        Desc='Opens the official GitHub page for Optimizer by hellzerg. A separate community tool. Use with care: some of its options can disable Defender/SmartScreen/Updates, which Velocity deliberately will not. Downloaded transparently from source.'
        Run={ Start-Process 'https://github.com/hellzerg/optimizer'; return 'Optimizer GitHub page opened in your browser.' } }

    [pscustomobject]@{ Id='devmgr'; Cat='System & Repair'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Open Device Manager'
        Desc='Check for devices with a yellow warning (missing drivers). Useful after a fresh Windows install.'
        Run={ Start-Process devmgmt.msc; return 'Device Manager opened.' } }

    [pscustomobject]@{ Id='display'; Cat='System & Repair'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Open Display Settings'
        Desc='Manage multiple monitors, set the main display and per-monitor refresh rate.'
        Run={ Start-Process 'ms-settings:display'; return 'Display settings opened.' } }

    [pscustomobject]@{ Id='gpucp'; Cat='System & Repair'; Type='Action'; Risk='Safe'; Reboot=$false
        Name='Open Graphics Control Panel'
        Desc='Detects your GPU (NVIDIA, AMD or Intel) and opens its control panel so you can set a high-performance power mode and low-latency options. Falls back to Display Settings.'
        Run={ $gpu = ((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Microsoft|Parsec|Meta' } | Select-Object -ExpandProperty Name) -join ' ')
              $opened=$false; $what=''
              if ($gpu -match 'NVIDIA') {
                  $p="$env:ProgramFiles\NVIDIA Corporation\Control Panel Client\nvcplui.exe"
                  if (Test-Path $p) { Start-Process $p; $opened=$true; $what='NVIDIA Control Panel' }
              } elseif ($gpu -match 'AMD|Radeon') {
                  foreach ($p in @("$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe","${env:ProgramFiles(x86)}\AMD\CNext\CNext\RadeonSoftware.exe")) {
                      if (Test-Path $p) { Start-Process $p; $opened=$true; $what='AMD Software'; break } }
              } elseif ($gpu -match 'Intel') {
                  try { Start-Process 'explorer.exe' 'shell:AppsFolder\AppUp.IntelGraphicsExperience_8j3eq9eme6ctt!AppUp.IntelGraphicsExperience'; $opened=$true; $what='Intel Graphics Command Center' } catch {}
              }
              if (-not $opened) { Start-Process 'ms-settings:display'; return 'No GPU vendor panel found - opened Display Settings instead.' }
              return ("Opened {0}." -f $what) } }
)

# ============================================================================
#  SYSTEM SNAPSHOT  (powers the Dashboard)
# ============================================================================
function Get-SystemSnapshot {
    $snap = [ordered]@{}
    try { $os = Get-CimInstance Win32_OperatingSystem; $dv = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
          $snap.OS = "$($os.Caption.Replace('Microsoft ','')) $dv (build $($os.BuildNumber))" } catch { $snap.OS = 'unknown' }
    try { $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
          $snap.CPU = "$($cpu.Name.Trim())  -  $($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T" } catch { $snap.CPU='unknown' }
    try { $ram = Get-CimInstance Win32_PhysicalMemory; $tot=($ram|Measure-Object Capacity -Sum).Sum/1GB
          $snap.RAM = "{0:N0} GB  {1} MHz" -f $tot, ($ram|Select-Object -First 1).Speed } catch { $snap.RAM='unknown' }
    try { $g = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote' } | Select-Object -First 1
          $snap.GPU = "$($g.Name)  -  driver $($g.DriverVersion)" } catch { $snap.GPU='unknown' }
    try { $bb=Get-CimInstance Win32_BaseBoard; $bios=Get-CimInstance Win32_BIOS
          $snap.Board = "$($bb.Manufacturer) $($bb.Product)"
          $snap.BiosDate = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate)
          $snap.Bios = "$($bios.SMBIOSBIOSVersion)  ($($snap.BiosDate.ToString('yyyy-MM-dd')))" } catch { $snap.Bios='unknown'; $snap.BiosDate=$null }
    try { $mons = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | ForEach-Object { (($_.UserFriendlyName | Where-Object {$_ -ne 0}) | ForEach-Object {[char]$_}) -join '' }
          $snap.Displays = ($mons -join ', ') } catch { $snap.Displays='unknown' }
    try { $snap.ProblemDevices = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne $null -and $_.ConfigManagerErrorCode -ne 0 } | Measure-Object).Count } catch { $snap.ProblemDevices=0 }
    try { $snap.Crashes = (Get-WinEvent -FilterHashtable @{LogName='System';Id=41;ProviderName='Microsoft-Windows-Kernel-Power';StartTime=(Get-Date).AddDays(-14)} -ErrorAction Stop | Measure-Object).Count } catch { $snap.Crashes=0 }
    try { $av = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { $_.displayName }
          $snap.AV = ($av -join ', ') } catch { $snap.AV='unknown' }
    $snap.MonitorCount = ($snap.Displays -split ',').Count
    return $snap
}

# ============================================================================
#  USER INTERFACE  (XAML defines the design system as resources)
# ============================================================================
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:sys="clr-namespace:System;assembly=mscorlib"
        Title="Velocity" Height="760" Width="1140" MinHeight="600" MinWidth="980"
        WindowStartupLocation="CenterScreen" Background="#0D0E12" FontFamily="Segoe UI"
        TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
    <!-- ===== COLOR TOKENS ===== -->
    <SolidColorBrush x:Key="Bg"        Color="#0D0E12"/>
    <SolidColorBrush x:Key="Surface"   Color="#15171E"/>
    <SolidColorBrush x:Key="Surface2"  Color="#1B1E27"/>
    <SolidColorBrush x:Key="Line"      Color="#262A36"/>
    <SolidColorBrush x:Key="Text"      Color="#ECEEF3"/>
    <SolidColorBrush x:Key="TextDim"   Color="#99A0AE"/>
    <SolidColorBrush x:Key="TextMute"  Color="#646B7A"/>
    <SolidColorBrush x:Key="Accent"    Color="#F2542D"/>
    <SolidColorBrush x:Key="Success"   Color="#34D399"/>
    <SolidColorBrush x:Key="Warning"   Color="#FBBF24"/>
    <SolidColorBrush x:Key="Danger"    Color="#F87171"/>
    <!-- ===== TYPE SCALE TOKENS ===== -->
    <sys:Double x:Key="FsDisplay">26</sys:Double>
    <sys:Double x:Key="FsH1">19</sys:Double>
    <sys:Double x:Key="FsH2">15</sys:Double>
    <sys:Double x:Key="FsBody">13</sys:Double>
    <sys:Double x:Key="FsSmall">12</sys:Double>
    <sys:Double x:Key="FsMicro">11</sys:Double>

    <!-- ===== SCROLLBAR (slim, themed) ===== -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="4" Background="#323848" Margin="2,0"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton><RepeatButton Opacity="0" Command="ScrollBar.PageDownCommand"/></Track.IncreaseRepeatButton>
                <Track.DecreaseRepeatButton><RepeatButton Opacity="0" Command="ScrollBar.PageUpCommand"/></Track.DecreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ===== NAV ITEM (RadioButton) ===== -->
    <Style x:Key="NavItem" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource TextDim}"/>
      <Setter Property="FontSize" Value="{StaticResource FsBody}"/>
      <Setter Property="FontWeight" Value="Medium"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="10,2"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" CornerRadius="10" Padding="14,10" Background="Transparent">
              <Grid>
                <Border x:Name="bar" Width="3" Height="16" CornerRadius="2" HorizontalAlignment="Left" Background="{StaticResource Accent}" Opacity="0"/>
                <ContentPresenter Margin="14,0,0,0" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#1B1E27"/>
                <Setter Property="Foreground" Value="{StaticResource Text}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#1B1E27"/>
                <Setter TargetName="bar" Property="Opacity" Value="1"/>
                <Setter Property="Foreground" Value="{StaticResource Text}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ===== PRIMARY BUTTON ===== -->
    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="{StaticResource FsBody}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="10" Padding="18,10" SnapsToDevicePixels="True">
              <Border.Background><SolidColorBrush Color="#F2542D"/></Border.Background>
              <Border.RenderTransform><TranslateTransform x:Name="t" Y="0"/></Border.RenderTransform>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <EventTrigger RoutedEvent="MouseEnter">
                <BeginStoryboard><Storyboard>
                  <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="Background.Color" To="#FF6E45" Duration="0:0:0.15"/>
                  <DoubleAnimation Storyboard.TargetName="t" Storyboard.TargetProperty="Y" To="-2" Duration="0:0:0.15"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                </Storyboard></BeginStoryboard>
              </EventTrigger>
              <EventTrigger RoutedEvent="MouseLeave">
                <BeginStoryboard><Storyboard>
                  <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="Background.Color" To="#F2542D" Duration="0:0:0.15"/>
                  <DoubleAnimation Storyboard.TargetName="t" Storyboard.TargetProperty="Y" To="0" Duration="0:0:0.15"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                </Storyboard></BeginStoryboard>
              </EventTrigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ===== GHOST BUTTON ===== -->
    <Style x:Key="GhostButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="FontSize" Value="{StaticResource FsBody}"/>
      <Setter Property="FontWeight" Value="Medium"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="10" Padding="16,9" Background="Transparent" BorderThickness="1" BorderBrush="{StaticResource Line}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#1B1E27"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#323848"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ===== TOGGLE SWITCH ===== -->
    <Style x:Key="ToggleSwitch" TargetType="ToggleButton">
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="track" CornerRadius="13" BorderThickness="1" BorderBrush="{StaticResource Line}">
              <Border.Background><SolidColorBrush Color="#262A36"/></Border.Background>
              <Border x:Name="thumb" Width="20" Height="20" CornerRadius="10" HorizontalAlignment="Left" Margin="3,0,0,0">
                <Border.Background><SolidColorBrush Color="#99A0AE"/></Border.Background>
                <Border.RenderTransform><TranslateTransform x:Name="tt" X="0"/></Border.RenderTransform>
              </Border>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Trigger.EnterActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="tt" Storyboard.TargetProperty="X" To="20" Duration="0:0:0.18"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                  <ColorAnimation Storyboard.TargetName="track" Storyboard.TargetProperty="Background.Color" To="#F2542D" Duration="0:0:0.18"/>
                  <ColorAnimation Storyboard.TargetName="thumb" Storyboard.TargetProperty="Background.Color" To="#FFFFFF" Duration="0:0:0.18"/>
                </Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="tt" Storyboard.TargetProperty="X" To="0" Duration="0:0:0.18"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                  <ColorAnimation Storyboard.TargetName="track" Storyboard.TargetProperty="Background.Color" To="#262A36" Duration="0:0:0.18"/>
                  <ColorAnimation Storyboard.TargetName="thumb" Storyboard.TargetProperty="Background.Color" To="#99A0AE" Duration="0:0:0.18"/>
                </Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="track" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <!-- ===== SHELL: sidebar + content ===== -->
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="232"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Sidebar -->
    <Border Grid.Column="0" Background="{StaticResource Surface}" BorderBrush="{StaticResource Line}" BorderThickness="0,0,1,0">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Margin="22,24,22,18">
          <StackPanel Orientation="Horizontal">
            <Border Width="30" Height="30" CornerRadius="8" Background="{StaticResource Accent}">
              <TextBlock Text="V" Foreground="White" FontWeight="Bold" FontSize="17" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
              <TextBlock Text="Velocity" Foreground="{StaticResource Text}" FontSize="17" FontWeight="SemiBold"/>
              <TextBlock Text="Performance Toolkit" Foreground="{StaticResource TextMute}" FontSize="11"/>
            </StackPanel>
          </StackPanel>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom" Margin="22,12,22,18">
          <Border Height="1" Background="{StaticResource Line}" Margin="0,0,0,12"/>
          <TextBlock x:Name="AdminBadge" FontSize="11" Foreground="{StaticResource TextMute}" TextWrapping="Wrap"/>
          <TextBlock Text="v1.0  -  reversible by design" FontSize="11" Foreground="{StaticResource TextMute}" Margin="0,6,0,0"/>
        </StackPanel>
        <StackPanel x:Name="NavPanel" Margin="0,4,0,0"/>
      </DockPanel>
    </Border>

    <!-- Content -->
    <Grid Grid.Column="1">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header -->
      <Grid Grid.Row="0" Margin="32,28,32,16">
        <StackPanel>
          <TextBlock x:Name="PageTitle" Text="Dashboard" Foreground="{StaticResource Text}" FontSize="{StaticResource FsDisplay}" FontWeight="SemiBold"/>
          <TextBlock x:Name="PageSubtitle" Text="A quick read on your system's health." Foreground="{StaticResource TextDim}" FontSize="{StaticResource FsBody}" Margin="0,4,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
          <Button x:Name="BtnRestore" Style="{StaticResource GhostButton}" Content="Create Restore Point" Margin="0,0,10,0"/>
          <Button x:Name="BtnApplyAll" Style="{StaticResource PrimaryButton}" Content="Apply Recommended"/>
        </StackPanel>
      </Grid>

      <!-- Scrollable body -->
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="32,0,28,8">
        <Grid x:Name="Body"/>
      </ScrollViewer>

      <!-- Status bar -->
      <Border Grid.Row="2" Background="{StaticResource Surface}" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0" Padding="32,12">
        <Grid>
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="{StaticResource Success}" VerticalAlignment="Center"/>
            <TextBlock x:Name="StatusText" Text="Ready." Foreground="{StaticResource TextDim}" FontSize="{StaticResource FsSmall}" Margin="10,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ProgressBar x:Name="Progress" Width="220" Height="6" HorizontalAlignment="Right" Minimum="0" Maximum="100" Value="0"
                       Background="#262A36" Foreground="{StaticResource Accent}" BorderThickness="0" Visibility="Collapsed"/>
        </Grid>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)

# --- grab named elements ---
$ui = @{}
'NavPanel','Body','PageTitle','PageSubtitle','BtnRestore','BtnApplyAll','StatusDot','StatusText','Progress','AdminBadge' |
    ForEach-Object { $ui[$_] = $window.FindName($_) }

$ui.AdminBadge.Text = if ($IsAdmin) { "Running as Administrator" } else { "Limited mode - some tweaks need admin" }

# resources for code-built UI
$R = @{}
'Bg','Surface','Surface2','Line','Text','TextDim','TextMute','Accent','Success','Warning','Danger' |
    ForEach-Object { $R[$_] = $window.FindResource($_) }
$ToggleStyle = $window.FindResource('ToggleSwitch')
$GhostStyle  = $window.FindResource('PrimaryButton')
$GhostBtn    = $window.FindResource('GhostButton')

# ---- status helper ----
function Set-Status([string]$msg, [string]$kind='info') {
    $ui.StatusText.Text = $msg
    $ui.StatusDot.Fill = switch ($kind) { 'ok' {$R.Success} 'warn' {$R.Warning} 'err' {$R.Danger} default {$R.Accent} }
}

# ---- chip factory ----
function New-Chip([string]$text, $brush) {
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = [Windows.CornerRadius]::new(6); $b.Padding = [Windows.Thickness]::new(8,3,8,3)
    $b.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(28,$brush.Color.R,$brush.Color.G,$brush.Color.B))
    $t = New-Object Windows.Controls.TextBlock; $t.Text=$text; $t.FontSize=11; $t.FontWeight='SemiBold'; $t.Foreground=$brush
    $b.Child=$t; $b
}

# ---- one tweak card ----
$script:RowRefs = @{}
function Test-ThermallyConstrained {
    # Cached once: true for laptops / portable / battery-backed systems where forcing max
    # clocks is risky. Desktops/towers return false. Used to surface per-machine warnings.
    if ($null -ne $Script:Constrained) { return $Script:Constrained }
    if ($env:VELOCITY_FORCE_CONSTRAINED -eq '1') { $Script:Constrained = $true; return $true }
    $c = $false
    try { if ((Get-CimInstance Win32_ComputerSystem).PCSystemType -eq 2) { $c = $true } } catch {}
    try { if (@(Get-CimInstance Win32_Battery).Count -gt 0) { $c = $true } } catch {}
    try { $ct = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
          if ($ct | Where-Object { $_ -in 8,9,10,11,12,14,30,31,32 }) { $c = $true } } catch {}
    $Script:Constrained = $c
    return $c
}

function New-TweakRow($tw) {
    $card = New-Object Windows.Controls.Border
    $card.Background=$R.Surface; $card.CornerRadius=[Windows.CornerRadius]::new(10)
    $card.BorderBrush=$R.Line; $card.BorderThickness=[Windows.Thickness]::new(1)
    $card.Padding=[Windows.Thickness]::new(18,15,18,15); $card.Margin=[Windows.Thickness]::new(0,0,0,10)
    $card.RenderTransform = New-Object Windows.Media.TranslateTransform

    $grid = New-Object Windows.Controls.Grid
    [void]$grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width='*'}))
    $c2=New-Object Windows.Controls.ColumnDefinition; $c2.Width='Auto'; [void]$grid.ColumnDefinitions.Add($c2)

    $left = New-Object Windows.Controls.StackPanel
    $titleRow = New-Object Windows.Controls.StackPanel; $titleRow.Orientation='Horizontal'
    $title = New-Object Windows.Controls.TextBlock; $title.Text=$tw.Name; $title.Foreground=$R.Text; $title.FontSize=15; $title.FontWeight='SemiBold'; $title.VerticalAlignment='Center'
    [void]$titleRow.Children.Add($title)
    if ($tw.Risk -eq 'Caution') { $chip=New-Chip 'Caution' $R.Warning; $chip.Margin=[Windows.Thickness]::new(10,0,0,0); [void]$titleRow.Children.Add($chip) }
    if ($tw.Risk -eq 'Security'){ $chip=New-Chip 'Security' $R.Success; $chip.Margin=[Windows.Thickness]::new(10,0,0,0); [void]$titleRow.Children.Add($chip) }
    if ($tw.PSObject.Properties['Reboot'] -and $tw.Reboot) { $chip=New-Chip 'Reboot' $R.TextMute; $chip.Margin=[Windows.Thickness]::new(8,0,0,0); [void]$titleRow.Children.Add($chip) }
    [void]$left.Children.Add($titleRow)
    $desc = New-Object Windows.Controls.TextBlock; $desc.Text=$tw.Desc; $desc.Foreground=$R.TextDim; $desc.FontSize=12; $desc.TextWrapping='Wrap'; $desc.Margin=[Windows.Thickness]::new(0,5,18,0); $desc.MaxWidth=620
    [void]$left.Children.Add($desc)
    if ($tw.PSObject.Properties['HwWarn'] -and $tw.HwWarn -and (Test-ThermallyConstrained)) {
        $warn = New-Object Windows.Controls.TextBlock
        $warn.Text = [char]0x26A0 + ' Not recommended on your hardware: ' + $tw.HwWarn
        $warn.Foreground=$R.Warning; $warn.FontSize=12; $warn.TextWrapping='Wrap'
        $warn.Margin=[Windows.Thickness]::new(0,6,18,0); $warn.MaxWidth=620
        [void]$left.Children.Add($warn)
    }
    [Windows.Controls.Grid]::SetColumn($left,0); [void]$grid.Children.Add($left)

    $right = New-Object Windows.Controls.StackPanel; $right.VerticalAlignment='Center'
    if ($tw.Type -eq 'Toggle') {
        $state = New-Object Windows.Controls.TextBlock; $state.FontSize=11; $state.FontWeight='SemiBold'; $state.HorizontalAlignment='Right'; $state.Margin=[Windows.Thickness]::new(0,0,0,6)
        $tg = New-Object Windows.Controls.Primitives.ToggleButton; $tg.Style=$ToggleStyle; $tg.HorizontalAlignment='Right'
        $applied = $false; try { $applied = [bool](& $tw.Test) } catch {}
        $tg.IsChecked = $applied
        $state.Text = if ($applied) {'Applied'} else {'Default'}
        $state.Foreground = if ($applied) {$R.Success} else {$R.TextMute}
        $tg.Tag = $tw
        $tg.Add_Click({
            param($s,$e)
            $t=$s.Tag
            try {
                Set-Status ("Applying: {0}..." -f $t.Name)
                if ($s.IsChecked) { & $t.Apply } else { & $t.Revert }
                $now = [bool](& $t.Test)
                $s.IsChecked = $now
                $st = $script:RowRefs[$t.Id].State
                $st.Text = if ($now){'Applied'} else {'Default'}
                $st.Foreground = if ($now){$R.Success} else {$R.TextMute}
                $msg = if ($now){'Enabled'} else {'Reverted'}
                Set-Status ("{0}: {1}." -f $t.Name,$msg) 'ok'
            } catch { Set-Status ("Failed: {0} - {1}" -f $t.Name,$_.Exception.Message) 'err' }
        })
        [void]$right.Children.Add($state); [void]$right.Children.Add($tg)
        $script:RowRefs[$tw.Id] = @{ Toggle=$tg; State=$state }
    } else {
        $btn = New-Object Windows.Controls.Button; $btn.Style=$GhostBtn; $btn.Content='Run'; $btn.MinWidth=92; $btn.Tag=$tw
        $btn.Add_Click({
            param($s,$e)
            $t=$s.Tag; $orig=$s.Content
            try {
                $s.IsEnabled=$false; $s.Content='Working...'; Set-Status ("Running: {0}..." -f $t.Name)
                $s.Dispatcher.Invoke([action]{}, 'Background')
                $res = & $t.Run
                Set-Status ([string]$res) 'ok'
            } catch { Set-Status ("Failed: {0} - {1}" -f $t.Name,$_.Exception.Message) 'err' }
            finally { $s.IsEnabled=$true; $s.Content=$orig }
        })
        [void]$right.Children.Add($btn)
    }
    [Windows.Controls.Grid]::SetColumn($right,1); [void]$grid.Children.Add($right)
    $card.Child=$grid
    return $card
}

# ---- section header ----
function New-SectionHeader([string]$text) {
    $row = New-Object Windows.Controls.StackPanel; $row.Orientation='Horizontal'; $row.Margin=[Windows.Thickness]::new(2,10,0,10)
    $tick = New-Object Windows.Controls.Border; $tick.Width=3; $tick.Height=12; $tick.CornerRadius=[Windows.CornerRadius]::new(2)
    $tick.Background=$R.Accent; $tick.VerticalAlignment='Center'; $tick.Margin=[Windows.Thickness]::new(0,0,8,0)
    $t = New-Object Windows.Controls.TextBlock
    $t.Text=$text.ToUpper(); $t.Foreground=$R.TextMute; $t.FontSize=11; $t.FontWeight='SemiBold'; $t.VerticalAlignment='Center'
    [void]$row.Children.Add($tick); [void]$row.Children.Add($t)
    $row
}

# ============================================================================
#  PAGES
# ============================================================================
$Categories = @('Performance','Latency & Input','Network','Privacy & Telemetry','Security','Cleanup','Debloat','System & Repair')
$script:Panels = @{}

function Build-CategoryPanel([string]$cat) {
    $sp = New-Object Windows.Controls.StackPanel
    foreach ($tw in ($Tweaks | Where-Object { $_.Cat -eq $cat })) { [void]$sp.Children.Add((New-TweakRow $tw)) }
    return $sp
}

function Build-Dashboard {
    $sp = New-Object Windows.Controls.StackPanel
    $script:DashHost = $sp
    # skeletons first
    for ($i=0; $i -lt 5; $i++) {
        $sk = New-Object Windows.Controls.Border
        $sk.Background=$R.Surface; $sk.CornerRadius=[Windows.CornerRadius]::new(10); $sk.Height=64; $sk.Margin=[Windows.Thickness]::new(0,0,0,10); $sk.Opacity=0.5
        [void]$sp.Children.Add($sk)
    }
    return $sp
}

function New-InfoCard([string]$label,[string]$value,$accent) {
    $card=New-Object Windows.Controls.Border; $card.Background=$R.Surface; $card.CornerRadius=[Windows.CornerRadius]::new(10)
    $card.BorderBrush=$R.Line; $card.BorderThickness=[Windows.Thickness]::new(1); $card.Padding=[Windows.Thickness]::new(18,14,18,14); $card.Margin=[Windows.Thickness]::new(0,0,0,10)
    $g=New-Object Windows.Controls.Grid
    [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width='160'}))
    [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width='*'}))
    $l=New-Object Windows.Controls.TextBlock; $l.Text=$label; $l.Foreground=$R.TextMute; $l.FontSize=12; $l.FontWeight='SemiBold'; $l.VerticalAlignment='Center'
    $v=New-Object Windows.Controls.TextBlock; $v.Text=$value; $v.Foreground=$(if($accent){$accent}else{$R.Text}); $v.FontSize=13; $v.TextWrapping='Wrap'; $v.VerticalAlignment='Center'
    [Windows.Controls.Grid]::SetColumn($l,0); [Windows.Controls.Grid]::SetColumn($v,1)
    [void]$g.Children.Add($l); [void]$g.Children.Add($v); $card.Child=$g; $card
}
function New-HealthCard([string]$title,[string]$detail,$brush,[string]$tag) {
    $card=New-Object Windows.Controls.Border; $card.Background=$R.Surface; $card.CornerRadius=[Windows.CornerRadius]::new(10)
    $card.BorderThickness=[Windows.Thickness]::new(1)
    $card.BorderBrush=(New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(70,$brush.Color.R,$brush.Color.G,$brush.Color.B)))
    $card.Padding=[Windows.Thickness]::new(18,14,18,14); $card.Margin=[Windows.Thickness]::new(0,0,0,10)
    $g=New-Object Windows.Controls.Grid
    [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width='*'}))
    $c2=New-Object Windows.Controls.ColumnDefinition; $c2.Width='Auto'; [void]$g.ColumnDefinitions.Add($c2)
    $st=New-Object Windows.Controls.StackPanel
    $tt=New-Object Windows.Controls.TextBlock; $tt.Text=$title; $tt.Foreground=$R.Text; $tt.FontSize=14; $tt.FontWeight='SemiBold'
    $dd=New-Object Windows.Controls.TextBlock; $dd.Text=$detail; $dd.Foreground=$R.TextDim; $dd.FontSize=12; $dd.TextWrapping='Wrap'; $dd.Margin=[Windows.Thickness]::new(0,4,12,0); $dd.MaxWidth=640
    [void]$st.Children.Add($tt); [void]$st.Children.Add($dd)
    [Windows.Controls.Grid]::SetColumn($st,0); [void]$g.Children.Add($st)
    $chip=New-Chip $tag $brush; $chip.VerticalAlignment='Center'; [Windows.Controls.Grid]::SetColumn($chip,1); [void]$g.Children.Add($chip)
    $card.Child=$g; $card
}

function Get-HealthScore($snap) {
    $score=100; $issues=@()
    if ($snap.ProblemDevices -gt 0) { $score -= [Math]::Min(30,8*$snap.ProblemDevices); $issues += ("{0} driver issue(s)" -f $snap.ProblemDevices) }
    if ($snap.Crashes -gt 0)        { $score -= [Math]::Min(20,7*$snap.Crashes);       $issues += ("{0} recent crash(es)" -f $snap.Crashes) }
    if ($snap.BiosDate -and $snap.BiosDate -lt (Get-Date).AddYears(-1)) { $score -= 12; $issues += 'BIOS over a year old' }
    if ($snap.MonitorCount -gt 1) { $issues += 'multi-display - watch HDMI' }
    if ($score -lt 0) { $score=0 }
    [pscustomobject]@{ Score=$score; Issues=$issues }
}

function New-SpecTile([string]$label,[string]$value) {
    $card=New-Object Windows.Controls.Border; $card.Background=$R.Surface; $card.CornerRadius=[Windows.CornerRadius]::new(10)
    $card.BorderBrush=$R.Line; $card.BorderThickness=[Windows.Thickness]::new(1); $card.Padding=[Windows.Thickness]::new(16,12,16,12); $card.Margin=[Windows.Thickness]::new(0,0,10,10)
    $stk=New-Object Windows.Controls.StackPanel
    $l=New-Object Windows.Controls.TextBlock; $l.Text=$label.ToUpper(); $l.Foreground=$R.TextMute; $l.FontSize=10; $l.FontWeight='SemiBold'
    $v=New-Object Windows.Controls.TextBlock; $v.Text=$value; $v.Foreground=$R.Text; $v.FontSize=13; $v.FontWeight='Medium'; $v.TextWrapping='Wrap'; $v.Margin=[Windows.Thickness]::new(0,4,0,0)
    [void]$stk.Children.Add($l); [void]$stk.Children.Add($v); $card.Child=$stk; $card
}

function New-HealthHero($snap) {
    $h=Get-HealthScore $snap; $score=$h.Score
    $brush = if ($score -ge 85) { $R.Success } elseif ($score -ge 60) { $R.Warning } else { $R.Danger }
    $verdict = if ($score -ge 85) { 'Healthy' } elseif ($score -ge 60) { 'Needs attention' } else { 'Action recommended' }
    $sub = if ($h.Issues.Count) { ($h.Issues -join '     ') } else { 'No issues detected - everything checks out.' }

    $card=New-Object Windows.Controls.Border; $card.Background=$R.Surface; $card.CornerRadius=[Windows.CornerRadius]::new(12)
    $card.BorderBrush=$R.Line; $card.BorderThickness=[Windows.Thickness]::new(1); $card.Padding=[Windows.Thickness]::new(24,20,24,22); $card.Margin=[Windows.Thickness]::new(0,2,0,16)
    $g=New-Object Windows.Controls.Grid
    $cA=New-Object Windows.Controls.ColumnDefinition; $cA.Width='Auto'; [void]$g.ColumnDefinitions.Add($cA)
    [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width='*'}))

    $scoreSP=New-Object Windows.Controls.StackPanel; $scoreSP.VerticalAlignment='Center'; $scoreSP.Margin=[Windows.Thickness]::new(0,0,28,0)
    $num=New-Object Windows.Controls.TextBlock; $num.Text=[string]$score; $num.Foreground=$brush; $num.FontSize=48; $num.FontWeight='SemiBold'; $num.HorizontalAlignment='Center'
    $lbl=New-Object Windows.Controls.TextBlock; $lbl.Text='HEALTH SCORE'; $lbl.Foreground=$R.TextMute; $lbl.FontSize=10; $lbl.FontWeight='SemiBold'; $lbl.HorizontalAlignment='Center'; $lbl.Margin=[Windows.Thickness]::new(0,2,0,0)
    [void]$scoreSP.Children.Add($num); [void]$scoreSP.Children.Add($lbl)
    [Windows.Controls.Grid]::SetColumn($scoreSP,0); [void]$g.Children.Add($scoreSP)

    $right=New-Object Windows.Controls.StackPanel; $right.VerticalAlignment='Center'
    $vt=New-Object Windows.Controls.TextBlock; $vt.Text=$verdict; $vt.Foreground=$R.Text; $vt.FontSize=19; $vt.FontWeight='SemiBold'
    $st=New-Object Windows.Controls.TextBlock; $st.Text=$sub; $st.Foreground=$R.TextDim; $st.FontSize=12; $st.TextWrapping='Wrap'; $st.Margin=[Windows.Thickness]::new(0,3,0,13)
    [void]$right.Children.Add($vt); [void]$right.Children.Add($st)
    $bar=New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'
    $filled=[int][Math]::Round($score/5.0)
    for ($i=0;$i -lt 20;$i++){ $seg=New-Object Windows.Controls.Border; $seg.Width=15; $seg.Height=6; $seg.CornerRadius=[Windows.CornerRadius]::new(2); $seg.Margin=[Windows.Thickness]::new(0,0,3,0); $seg.Background=$(if ($i -lt $filled){$brush}else{$R.Line}); [void]$bar.Children.Add($seg) }
    [void]$right.Children.Add($bar)
    [Windows.Controls.Grid]::SetColumn($right,1); [void]$g.Children.Add($right)
    $card.Child=$g; $card
}

function Populate-Dashboard($snap) {
    $sp = $script:DashHost
    $sp.Children.Clear()
    [void]$sp.Children.Add((New-HealthHero $snap))
    [void]$sp.Children.Add((New-SectionHeader 'System'))
    $ug = New-Object Windows.Controls.Primitives.UniformGrid; $ug.Columns=2
    foreach ($pair in @(
        @('Processor',$snap.CPU),       @('Graphics',$snap.GPU),
        @('Memory',$snap.RAM),          @('Motherboard',$snap.Board),
        @('BIOS',$snap.Bios),           @('Operating System',$snap.OS),
        @('Displays',$snap.Displays),   @('Security',$snap.AV))) {
        [void]$ug.Children.Add((New-SpecTile $pair[0] $pair[1]))
    }
    [void]$sp.Children.Add($ug)

    [void]$sp.Children.Add((New-SectionHeader 'Health Checks'))
    # BIOS age
    $biosOld = $snap.BiosDate -and $snap.BiosDate -lt (Get-Date).AddYears(-1)
    if ($biosOld) { [void]$sp.Children.Add((New-HealthCard 'BIOS is over a year old' ("Dated {0}. If you run a 13th/14th-gen Intel CPU, update for the microcode stability fix." -f $snap.BiosDate.ToString('yyyy-MM-dd')) $R.Warning 'Review')) }
    else { [void]$sp.Children.Add((New-HealthCard 'BIOS is reasonably current' 'No action needed.' $R.Success 'OK')) }
    # drivers
    if ($snap.ProblemDevices -gt 0) { [void]$sp.Children.Add((New-HealthCard ("{0} device(s) missing drivers" -f $snap.ProblemDevices) 'Open Device Manager (System & Repair) and install chipset drivers from your board vendor.' $R.Warning 'Action')) }
    else { [void]$sp.Children.Add((New-HealthCard 'All devices have drivers' 'No yellow-flag devices found.' $R.Success 'OK')) }
    # multi-display
    if ($snap.MonitorCount -gt 1) { [void]$sp.Children.Add((New-HealthCard 'Multiple displays connected' 'If you see black-outs or the desktop rearranging, a second display (especially a TV on HDMI) dropping signal is the usual cause. Use a certified cable and disable the TV''s HDMI-CEC / auto-standby.' $R.Accent 'Note')) }
    # crashes
    if ($snap.Crashes -gt 0) { [void]$sp.Children.Add((New-HealthCard ("{0} unexpected shutdown(s) in 14 days" -f $snap.Crashes) 'Kernel-Power 41 events. Watch for thermals, PSU and (on 13th/14th-gen Intel) BIOS microcode.' $R.Warning 'Review')) }
    else { [void]$sp.Children.Add((New-HealthCard 'No recent unexpected shutdowns' 'System has been stable for 14 days.' $R.Success 'OK')) }

    # staggered fade-in
    $i=0
    foreach ($child in $sp.Children) {
        $child.Opacity=0
        $anim=New-Object Windows.Media.Animation.DoubleAnimation(0,1,([Windows.Duration][TimeSpan]::FromMilliseconds(260)))
        $anim.BeginTime=[TimeSpan]::FromMilliseconds(40*$i)
        $anim.EasingFunction=New-Object Windows.Media.Animation.CubicEase -Property @{EasingMode='EaseOut'}
        $child.BeginAnimation([Windows.UIElement]::OpacityProperty,$anim)
        $i++
    }
}

# ---- build nav + panels ----
$PageMeta = @{
    'Dashboard'           = 'A quick read on your system''s health.'
    'Performance'         = 'Proven GPU/CPU tweaks that raise real frame rates.'
    'Latency & Input'     = 'Lower input lag and make the desktop feel instant.'
    'Network'             = 'Trim networking overhead for online play.'
    'Privacy & Telemetry' = 'Stop the tracking without breaking security.'
    'Security'            = 'Restore protections that booster packs disable.'
    'Cleanup'             = 'Reclaim space and clear stale caches.'
    'Debloat'             = 'Remove ad-ware Store apps. Keeps anything you game with.'
    'System & Repair'     = 'Restore points, file repair, drivers and external tools.'
}
$navItems = @('Dashboard') + $Categories
$first=$true
foreach ($name in $navItems) {
    $rb = New-Object Windows.Controls.RadioButton; $rb.Style=$window.FindResource('NavItem'); $rb.Content=$name; $rb.GroupName='nav'; $rb.Tag=$name
    if ($first){ $rb.IsChecked=$true; $first=$false }
    $rb.Add_Checked({
        param($s,$e)
        $n=$s.Tag
        $ui.PageTitle.Text=$n
        $ui.PageSubtitle.Text=$PageMeta[$n]
        $ui.Body.Children.Clear()
        if (-not $script:Panels.ContainsKey($n)) { $script:Panels[$n] = if ($n -eq 'Dashboard'){ Build-Dashboard } else { Build-CategoryPanel $n } }
        [void]$ui.Body.Children.Add($script:Panels[$n])
        # fade content
        $script:Panels[$n].Opacity=0
        $a=New-Object Windows.Media.Animation.DoubleAnimation(0,1,([Windows.Duration][TimeSpan]::FromMilliseconds(200)))
        $script:Panels[$n].BeginAnimation([Windows.UIElement]::OpacityProperty,$a)
        if ($n -eq 'Dashboard' -and -not $script:DashLoaded) { Start-DashboardScan }
    })
    [void]$ui.NavPanel.Children.Add($rb)
}

# ---- dashboard scan (async via runspace, polled by a timer) ----
$script:DashLoaded=$false
function Start-DashboardScan {
    Set-Status 'Scanning system...'
    $sync=[hashtable]::Synchronized(@{done=$false; snap=$null})
    $script:scanSync=$sync
    $rs=[runspacefactory]::CreateRunspace(); $rs.ApartmentState='STA'; $rs.ThreadOptions='ReuseThread'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync',$sync)
    $rs.SessionStateProxy.SetVariable('fn',${function:Get-SystemSnapshot}.ToString())
    $ps=[powershell]::Create(); $ps.Runspace=$rs
    [void]$ps.AddScript('Set-Item function:Get-SystemSnapshot $fn; $sync.snap = Get-SystemSnapshot; $sync.done=$true')
    $script:scanHandle=$ps.BeginInvoke()
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        if ($script:scanSync.done) {
            $this.Stop()
            Populate-Dashboard $script:scanSync.snap
            $script:DashLoaded=$true
            Set-Status 'System scan complete.' 'ok'
        }
    })
    $timer.Start()
}

# ---- header buttons ----
$ui.BtnRestore.Add_Click({
    try { $ui.BtnRestore.IsEnabled=$false; $ui.BtnRestore.Content='Creating...'; Set-Status 'Creating restore point...'
          $ui.BtnRestore.Dispatcher.Invoke([action]{}, 'Background')
          Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
          Set-RegDword 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
          Checkpoint-Computer -Description ('Velocity {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType 'MODIFY_SETTINGS'
          Set-Status 'Restore point created.' 'ok' }
    catch { Set-Status ("Restore point failed: {0}" -f $_.Exception.Message) 'err' }
    finally { $ui.BtnRestore.IsEnabled=$true; $ui.BtnRestore.Content='Create Restore Point' }
})

$ui.BtnApplyAll.Add_Click({
    $safe = $Tweaks | Where-Object { $_.Type -eq 'Toggle' -and $_.Risk -in 'Safe','Security' }
    $res=[Windows.MessageBox]::Show(("Apply {0} recommended (safe + security) tweaks now?`n`nCaution-level items (networking) and one-shot actions are left for you to choose manually." -f $safe.Count),'Velocity','YesNo','Question')
    if ($res -ne 'Yes') { return }
    $ui.BtnApplyAll.IsEnabled=$false; $ui.Progress.Visibility='Visible'; $ui.Progress.Value=0
    $n=$safe.Count; $i=0
    foreach ($t in $safe) {
        try { Set-Status ("Applying: {0}..." -f $t.Name); & $t.Apply
              if ($script:RowRefs.ContainsKey($t.Id)) { $now=[bool](& $t.Test); $rr=$script:RowRefs[$t.Id]; $rr.Toggle.IsChecked=$now; $rr.State.Text=if($now){'Applied'}else{'Default'}; $rr.State.Foreground=if($now){$R.Success}else{$R.TextMute} } }
        catch {}
        $i++; $ui.Progress.Value=[int](100*$i/$n)
        $ui.Progress.Dispatcher.Invoke([action]{}, 'Background')
    }
    Set-Status ("Applied {0} recommended tweaks. A reboot finishes GPU scheduling changes." -f $n) 'ok'
    $ui.BtnApplyAll.IsEnabled=$true
    $ui.Progress.Visibility='Collapsed'
})

# enable dark title bar (best-effort)
Add-Type -Namespace Win -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr h,int a,int[] v,int s);' -ErrorAction SilentlyContinue
$window.Add_SourceInitialized({
    try { $h=(New-Object Windows.Interop.WindowInteropHelper $window).Handle; [Win.Dwm]::DwmSetWindowAttribute($h,20,@(1),4) | Out-Null } catch {}
})

# initial page
$ui.Body.Children.Clear()
$script:Panels['Dashboard']=Build-Dashboard
[void]$ui.Body.Children.Add($script:Panels['Dashboard'])

if ($Test) {
    # headless validation: run the scan synchronously, no window shown
    Populate-Dashboard (Get-SystemSnapshot)
    foreach ($c in $Categories) { [void](Build-CategoryPanel $c) }
    Write-Host "SELFTEST OK - window built, $($Tweaks.Count) tweaks, $($Categories.Count) categories."
    return
}

$window.Add_ContentRendered({ Start-DashboardScan })
[void]$window.ShowDialog()
