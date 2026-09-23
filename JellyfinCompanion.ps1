param([switch]$StartMonitoring, [switch]$Check, [switch]$SmokeTest, [string]$DiagnosticsPath,
    [ValidateSet('Sleep','Shutdown')][string]$PowerAction = 'Sleep',
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'JellyfinCompanion'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Core.ps1')
. (Join-Path $PSScriptRoot 'src\Settings.ps1')
$settingsError = $null
try { Initialize-CompanionSettings $DataDirectory }
catch { $settingsError = 'Settings could not load. Open Connection settings to repair them.' }

if ($Check) {
    if ($settingsError) { throw $settingsError }
    $sessions = @(Get-ServerSessions)
    $decision = Get-IdleDecision $sessions 0 $null $null
    [pscustomobject]@{Server=$script:ServerUrl;Sessions=$sessions.Count;Playing=$decision.Playing;MonitoringArmed=$false;PowerAction=$PowerAction;Connection='OK'} | Format-List
    @(Get-JellyfinAddresses) | Select-Object Adapter,Url,Listening | Format-Table
    exit 0
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$created = $false
$mutexName = if ($SmokeTest) { 'Local\JellyfinCompanion-SmokeTest' } else { 'Local\JellyfinCompanion' }
$mutex = [System.Threading.Mutex]::new($true, $mutexName, [ref]$created)
if (-not $created) {
    [System.Windows.Forms.MessageBox]::Show('Jellyfin Companion is already open. Use its window to start or stop monitoring.', 'Jellyfin Companion') | Out-Null
    $mutex.Dispose(); exit 0
}

$script:armed = $false
$script:powerAction = $PowerAction
$script:idleSince = $null
$script:previousCheck = $null
$script:nextCheck = 0.0
$script:nextAddressCheck = 0.0
$script:busy = $false
$script:clock = [System.Diagnostics.Stopwatch]::StartNew()
$script:playing = 0
$script:sessionCount = 0
$script:connectionState = 'Not checked'
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Jellyfin Companion'
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96,96)
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Object System.Drawing.Size(720,674)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(16,21,30)
$form.ForeColor = [System.Drawing.Color]::FromArgb(237,243,252)
$form.Font = New-Object System.Drawing.Font('Segoe UI',10)
$muted = [System.Drawing.Color]::FromArgb(163,179,200)
$accent = [System.Drawing.Color]::FromArgb(104,220,232)

function Add-Label($text,$x,$y,$width,$height,$size=10,$parent=$form) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text=$text; $label.SetBounds($x,$y,$width,$height)
    $label.Font=New-Object System.Drawing.Font('Segoe UI',$size)
    $label.BackColor=[System.Drawing.Color]::Transparent
    $parent.Controls.Add($label); return $label
}
function Add-Button($text,$x,$y,$width,$parent=$form) {
    $button=New-Object System.Windows.Forms.Button
    $button.Text=$text; $button.SetBounds($x,$y,$width,38)
    $button.FlatStyle='Flat'; $button.FlatAppearance.BorderSize=0
    $button.BackColor=[System.Drawing.Color]::FromArgb(43,57,77)
    $button.FlatAppearance.MouseOverBackColor=[System.Drawing.Color]::FromArgb(57,76,100)
    $button.FlatAppearance.MouseDownBackColor=[System.Drawing.Color]::FromArgb(35,48,66)
    $button.Cursor=[System.Windows.Forms.Cursors]::Hand
    $parent.Controls.Add($button); return $button
}
function Add-Card($x,$y,$width,$height) {
    $panel=New-Object System.Windows.Forms.Panel
    $panel.SetBounds($x,$y,$width,$height)
    $panel.BackColor=[System.Drawing.Color]::FromArgb(27,35,48)
    $form.Controls.Add($panel); return $panel
}
$null=Add-Label 'Jellyfin Companion' 24 20 460 38 22
$subtitle=Add-Label 'Your server, at a glance.' 26 62 450 25 10
$subtitle.ForeColor=$muted
$settingsButton=Add-Button 'Connection settings' 526 28 170

$networkCard=Add-Card 24 104 672 256
$networkHeading=Add-Label 'Network connection' 20 14 632 26 13 $networkCard
$networkHint=Add-Label 'Use any device on the same Wi-Fi or Ethernet network.' 20 43 632 22 9 $networkCard
$networkHint.ForeColor=$muted
$networkSelector=New-Object System.Windows.Forms.ComboBox
$networkSelector.SetBounds(20,70,632,30)
$networkSelector.DropDownStyle='DropDownList'; $networkSelector.FlatStyle='Flat'
$networkSelector.BackColor=[System.Drawing.Color]::FromArgb(43,57,77)
$networkSelector.ForeColor=$form.ForeColor
$networkSelector.DisplayMember='Display'; $networkSelector.AccessibleName='Network connection'
$networkSelector.DrawMode='OwnerDrawFixed'; $networkSelector.ItemHeight=24
$networkSelector.Add_DrawItem({
    param($sender,$eventArgs)
    $background=[System.Drawing.Color]::FromArgb(43,57,77)
    if (($eventArgs.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) {
        $background=[System.Drawing.Color]::FromArgb(55,76,100)
    }
    $brush=New-Object System.Drawing.SolidBrush($background)
    try { $eventArgs.Graphics.FillRectangle($brush,$eventArgs.Bounds) } finally { $brush.Dispose() }
    $text=if ($eventArgs.Index -ge 0) { $sender.Items[$eventArgs.Index].Display } else { $sender.Text }
    $bounds=New-Object System.Drawing.Rectangle(($eventArgs.Bounds.X+8),$eventArgs.Bounds.Y,([Math]::Max(1,$eventArgs.Bounds.Width-16)),$eventArgs.Bounds.Height)
    $flags=[System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    [System.Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics,[string]$text,$sender.Font,$bounds,$sender.ForeColor,$flags)
})
$networkCard.Controls.Add($networkSelector)
$addressPanel=New-Object System.Windows.Forms.Panel
$addressPanel.SetBounds(20,112,632,44)
$addressPanel.BackColor=[System.Drawing.Color]::FromArgb(17,25,36)
$networkCard.Controls.Add($addressPanel)
$urlBox=New-Object System.Windows.Forms.TextBox
$urlBox.SetBounds(12,7,608,30); $urlBox.ReadOnly=$true; $urlBox.BorderStyle='None'
$urlBox.Font=New-Object System.Drawing.Font('Segoe UI',17)
$urlBox.BackColor=$addressPanel.BackColor; $urlBox.ForeColor=$accent
$urlBox.AccessibleName='Jellyfin server address'
$addressPanel.Controls.Add($urlBox)
$copy=Add-Button 'Copy address' 20 170 202 $networkCard
$open=Add-Button 'Open Jellyfin' 234 170 202 $networkCard
$refresh=Add-Button 'Refresh' 448 170 204 $networkCard
$addressStatus=Add-Label 'Checking your network...' 20 223 632 22 9 $networkCard
$addressStatus.ForeColor=$muted

$sleepCard=Add-Card 24 376 672 220
$null=Add-Label 'When playback stops' 20 14 370 27 13 $sleepCard
$sleepOption=New-Object System.Windows.Forms.RadioButton
$sleepOption.Text='Sleep'; $sleepOption.SetBounds(425,14,85,28)
$sleepOption.FlatStyle='Flat'; $sleepCard.Controls.Add($sleepOption)
$shutdownOption=New-Object System.Windows.Forms.RadioButton
$shutdownOption.Text='Shut down'; $shutdownOption.SetBounds(524,14,128,28)
$shutdownOption.FlatStyle='Flat'; $sleepCard.Controls.Add($shutdownOption)
$sleepOption.Checked=$script:powerAction -eq 'Sleep'
$shutdownOption.Checked=$script:powerAction -eq 'Shutdown'
$actionDescription=Add-Label 'Sleep after 5 minutes without playback.' 20 47 632 24 11 $sleepCard
$sleepHint=Add-Label 'Disconnects Wi-Fi first. Paused playback counts as idle.' 20 77 632 23 9 $sleepCard
$sleepHint.ForeColor=$muted
$sleepStatus=Add-Label 'Auto sleep is OFF' 20 111 632 27 10 $sleepCard
$countdown=Add-Label 'PC stays on' 20 148 390 52 25 $sleepCard
$countdown.ForeColor=$accent
$toggle=Add-Button 'Start auto sleep' 436 151 216 $sleepCard
$toggle.Height=42
$toggle.BackColor=$accent
$toggle.ForeColor=[System.Drawing.Color]::FromArgb(16,28,38)
$toggle.Font=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$toggle.FlatAppearance.MouseOverBackColor=[System.Drawing.Color]::FromArgb(137,235,244)
$toggle.FlatAppearance.MouseDownBackColor=[System.Drawing.Color]::FromArgb(75,193,207)
$hint=Add-Label 'Minimize to keep monitoring. Closing cancels the timer.' 24 613 540 24 9
$hint.ForeColor=$muted
$updated=Add-Label 'Network addresses refresh every 10 seconds.' 24 643 540 22 9
$updated.ForeColor=$muted
$close=Add-Button 'Close' 586 616 110
function Write-MonitorState {
    try {
        [pscustomobject]@{Time=(Get-Date -Format o);ProcessId=$PID;MonitoringArmed=$script:armed;PowerAction=$script:powerAction;Status=$sleepStatus.Text;Countdown=$countdown.Text;Connection=$script:connectionState;Sessions=$script:sessionCount;Playing=$script:playing} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:CompanionData 'monitor-state.json')
    } catch { }
}
function Set-MonitorStopped {
    $script:armed=$false; $script:idleSince=$null; $script:previousCheck=$null
    $sleepOption.Enabled=$true; $shutdownOption.Enabled=$true
    if ($script:powerAction -eq 'Shutdown') {
        $toggle.Text='Start auto shutdown'; $sleepStatus.Text='Auto shutdown is OFF'
        $actionDescription.Text='Shut down after 5 minutes without playback.'
        $sleepHint.Text='Wi-Fi disconnects first. Paused counts as idle. Save your work.'
    } else {
        $toggle.Text='Start auto sleep'; $sleepStatus.Text='Auto sleep is OFF'
        $actionDescription.Text='Sleep after 5 minutes without playback.'
        $sleepHint.Text='Disconnects Wi-Fi first. Paused playback counts as idle.'
    }
    $countdown.Text='PC stays on'
    Write-MonitorState
}
function Start-Monitor {
    if ($SmokeTest) { return }
    if (-not $script:ApiKey) {
        $sleepStatus.Text='Add an API key in Connection settings first.'
        return
    }
    $script:armed=$true; $script:idleSince=$null; $script:previousCheck=$null; $script:nextCheck=0
    $sleepOption.Enabled=$false; $shutdownOption.Enabled=$false
    $toggle.Text=if ($script:powerAction -eq 'Shutdown') {'Stop auto shutdown'} else {'Stop auto sleep'}
    $sleepStatus.Text='Checking playback...'; $countdown.Text='05:00'
    Write-MonitorState
}
function Show-SelectedAddress {
    $item=$networkSelector.SelectedItem
    $copy.Enabled=$null -ne $item; $open.Enabled=$null -ne $item
    if ($null -eq $item) {
        $urlBox.Text=''; $addressStatus.Text='No local network found. Connect this PC to Wi-Fi or Ethernet.'
        return
    }
    $urlBox.Text=$item.Url
    $addressStatus.Text=if ($item.Listening) {
        'Server port is listening. Ready for devices on this network.'
    } else { 'Server port is not listening. Start Jellyfin and refresh.' }
}
function Update-Addresses {
    $oldAdapter=if ($networkSelector.SelectedItem) {$networkSelector.SelectedItem.Adapter} else {''}
    $networkSelector.BeginUpdate()
    try {
        $items=@(Get-JellyfinAddresses | Sort-Object Priority,Network)
        $networkSelector.Items.Clear(); $selected=0
        foreach ($item in $items) {
            $index=$networkSelector.Items.Add($item)
            if ($item.Adapter -eq $oldAdapter) {$selected=$index}
        }
        if ($items.Count -gt 0) {$networkSelector.SelectedIndex=$selected}
        Show-SelectedAddress
        $updated.Text='Address updated ' + (Get-Date -Format 'h:mm:ss tt') + ' | Auto-refresh: 10 seconds'
    } catch {
        $networkSelector.Items.Clear(); Show-SelectedAddress
        $addressStatus.Text='Could not read network details. Click Refresh to retry.'
    } finally { $networkSelector.EndUpdate() }
    $script:nextAddressCheck=$script:clock.Elapsed.TotalSeconds+10
}
function Show-ConnectionSettings {
    Set-MonitorStopped
    $dialog=New-Object System.Windows.Forms.Form
    $dialog.Text='Jellyfin connection settings'; $dialog.ClientSize=New-Object System.Drawing.Size(540,275)
    $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
    $dialog.Font=New-Object System.Drawing.Font('Segoe UI',10)
    $dialog.BackColor=$form.BackColor; $dialog.ForeColor=$form.ForeColor
    $urlLabel=New-Object System.Windows.Forms.Label; $urlLabel.Text='Local Jellyfin server URL'; $urlLabel.SetBounds(20,18,500,24); $dialog.Controls.Add($urlLabel)
    $serverInput=New-Object System.Windows.Forms.TextBox; $serverInput.Text=$script:ServerUrl; $serverInput.SetBounds(20,46,500,28); $dialog.Controls.Add($serverInput)
    $keyLabel=New-Object System.Windows.Forms.Label; $keyLabel.Text='API key (leave blank to keep your saved key)'; $keyLabel.SetBounds(20,88,500,24); $dialog.Controls.Add($keyLabel)
    $keyInput=New-Object System.Windows.Forms.TextBox; $keyInput.UseSystemPasswordChar=$true; $keyInput.SetBounds(20,116,500,28); $dialog.Controls.Add($keyInput)
    $note=New-Object System.Windows.Forms.Label; $note.Text='Create a key in Jellyfin Dashboard > API Keys. It is saved encrypted for your Windows account.'; $note.SetBounds(20,158,500,48); $dialog.Controls.Add($note)
    $save=New-Object System.Windows.Forms.Button; $save.Text='Test and save'; $save.SetBounds(20,218,165,36); $dialog.Controls.Add($save)
    $cancel=New-Object System.Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.SetBounds(355,218,165,36); $dialog.Controls.Add($cancel)
    foreach ($inputBox in @($serverInput,$keyInput)) {
        $inputBox.BackColor=[System.Drawing.Color]::FromArgb(43,57,77)
        $inputBox.ForeColor=$form.ForeColor; $inputBox.BorderStyle='FixedSingle'
    }
    $note.ForeColor=$muted
    foreach ($actionButton in @($save,$cancel)) {
        $actionButton.FlatStyle='Flat'; $actionButton.FlatAppearance.BorderSize=0
        $actionButton.BackColor=[System.Drawing.Color]::FromArgb(43,57,77)
        $actionButton.Cursor=[System.Windows.Forms.Cursors]::Hand
    }
    $save.BackColor=$accent; $save.ForeColor=[System.Drawing.Color]::FromArgb(16,28,38)
    $cancel.Add_Click({$dialog.Close()})
    $save.Add_Click({
        $candidate=if ($keyInput.Text.Trim()) {$keyInput.Text.Trim()} else {$script:ApiKey}
        try {
            Save-CompanionSettings -Url $serverInput.Text.Trim() -ApiKey $candidate
            $sleepStatus.Text='Connection verified. Choose an action, then click Start.'
            $script:connectionState='OK'; $dialog.Close()
        } catch { $note.Text='Could not verify the connection. Check the local URL and API key.' }
    })
    $null=$dialog.ShowDialog($form)
    $keyInput.Text=''; $dialog.Dispose()
}

$networkSelector.Add_SelectedIndexChanged({Show-SelectedAddress})
$sleepOption.Add_CheckedChanged({if ($sleepOption.Checked) {$script:powerAction='Sleep'; Set-MonitorStopped}})
$shutdownOption.Add_CheckedChanged({if ($shutdownOption.Checked) {$script:powerAction='Shutdown'; Set-MonitorStopped}})
$refresh.Add_Click({Update-Addresses})
$copy.Add_Click({
    if ($urlBox.Text) {
        try {[System.Windows.Forms.Clipboard]::SetText($urlBox.Text); $updated.Text='Address copied.'}
        catch {$updated.Text='Could not copy. Select the address and press Ctrl+C.'}
    }
})
$open.Add_Click({if ($urlBox.Text) {Start-Process -FilePath $urlBox.Text}})
$toggle.Add_Click({if ($script:armed) {Set-MonitorStopped} else {Start-Monitor}})
$settingsButton.Add_Click({Show-ConnectionSettings})
$close.Add_Click({$form.Close()})
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=500
$timer.Add_Tick({
    if ($script:busy) {return}
    $script:busy=$true
    try {
        $now=$script:clock.Elapsed.TotalSeconds
        if ($now -ge $script:nextAddressCheck) {Update-Addresses}
        if (-not $script:armed) {return}
        if ($now -lt $script:nextCheck) {
            if ($null -ne $script:idleSince) {
                $left=[Math]::Max(0,[Math]::Ceiling(300-($now-$script:idleSince)))
                $countdown.Text='{0:00}:{1:00}' -f [int][Math]::Floor($left/60),[int]($left%60)
            }
            return
        }
        try {
            $sessions=@(Get-ServerSessions)
            $now=$script:clock.Elapsed.TotalSeconds
            $decision=Get-IdleDecision $sessions $now $script:idleSince $script:previousCheck
            $script:connectionState='OK'; $script:sessionCount=$sessions.Count; $script:playing=$decision.Playing
            $script:previousCheck=$now; $script:idleSince=$decision.IdleSince
            switch ($decision.Mode) {
                'Playing' {$sleepStatus.Text='Playback active on {0} device(s)' -f $decision.Playing; $countdown.Text='PC stays on'}
                'Idle' {
                    $sleepStatus.Text=if ($script:powerAction -eq 'Shutdown') {'Nobody is playing - shutdown countdown'} else {'Nobody is playing - sleep countdown'}
                    $countdown.Text='{0:00}:{1:00}' -f [int][Math]::Floor($decision.Remaining/60),[int]($decision.Remaining%60)
                }
                'Due' {
                    Set-MonitorStopped
                    $sleepOption.Enabled=$false; $shutdownOption.Enabled=$false
                    $sleepStatus.Text='Disconnecting Wi-Fi and requesting ' + $script:powerAction.ToLower() + '...'
                    $countdown.Text=if ($script:powerAction -eq 'Shutdown') {'Shutting down'} else {'Going to sleep'}
                    Write-MonitorState
                    Write-CompanionLog ('Five minutes of confirmed playback inactivity. Disconnecting Wi-Fi, then requesting ' + $script:powerAction + '.')
                    Invoke-IdlePowerAction -Action $script:powerAction
                    Write-CompanionLog ($script:powerAction + ' request returned. Monitoring remains OFF.')
                    Set-MonitorStopped
                    $sleepStatus.Text=if ($script:powerAction -eq 'Shutdown') {'Shutdown requested. Unsaved work may block it.'} else {'Auto sleep is OFF. Reconnect Wi-Fi if needed.'}
                }
            }
        } catch {
            $script:idleSince=$null; $script:previousCheck=$null
            if ($script:armed) {$script:connectionState='Unavailable'; $sleepStatus.Text='Cannot verify playback - countdown reset'}
            else {Set-MonitorStopped; $sleepStatus.Text='Power action failed. Monitoring is OFF.'; Write-CompanionLog 'Wi-Fi disconnect or power action failed. No further action will run until started again.'}
            $countdown.Text='PC stays on'
        } finally {$script:nextCheck=$script:clock.Elapsed.TotalSeconds+5; Write-MonitorState}
    } finally {$script:busy=$false}
})
$form.Add_Shown({
    Update-Addresses
    Set-MonitorStopped
    if ($settingsError) {$sleepStatus.Text=$settingsError}
    elseif (-not $script:ApiKey) {$sleepStatus.Text='Set up your API key in Connection settings to enable the timer.'}
    if ($StartMonitoring -and -not $SmokeTest) {Start-Monitor}
    Write-MonitorState
    if ($SmokeTest) {
        if (-not $DiagnosticsPath) {throw 'SmokeTest requires DiagnosticsPath.'}
        New-Item -ItemType Directory -Path $DiagnosticsPath -Force | Out-Null
        $bitmap=New-Object System.Drawing.Bitmap($form.Width,$form.Height)
        $form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)))
        $bitmap.Save((Join-Path $DiagnosticsPath 'companion.png'),[System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        [pscustomobject]@{Title=$form.Text;MonitoringArmed=$script:armed;PowerAction=$script:powerAction;StartButton=$toggle.Text;ActionDescription=$actionDescription.Text;SleepSelected=$sleepOption.Checked;ShutdownSelected=$shutdownOption.Checked;AddressCount=$networkSelector.Items.Count;Address=$urlBox.Text;Status=$sleepStatus.Text;Controls=$form.Controls.Count} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $DiagnosticsPath 'ui-test.json')
        $form.Close(); return
    }
    $timer.Start()
})
$form.Add_FormClosing({$script:armed=$false; $timer.Stop(); Write-MonitorState})
try {[System.Windows.Forms.Application]::Run($form)}
finally {$timer.Dispose(); $form.Dispose(); $mutex.ReleaseMutex(); $mutex.Dispose()}
