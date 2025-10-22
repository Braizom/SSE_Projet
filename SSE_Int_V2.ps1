Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$FolderPathList = [System.Collections.ArrayList]@()
$FilePathList = [System.Collections.ArrayList]@()

Function FindSmtp($email){
    $smtp = "smtp."
    $domain = $email.Split("@")[-1]
    return ($smtp + $domain)
}

class Smtp{
    [string]$Server
    [int]$Port
    [bool]$UseTls
    [string]$From
    [string]$To
    [string]$Username
    [string]$Password

    Smtp($user, $passwrd){
        Write-Host "WRITING SMTP"
        $this.Server = FindSmtp($user)
        $this.Port = 587
        $this.UseTls = $true
        $this.From = $user
        $this.To = $user
        $this.Username = $user
        $this.Password = $passwrd
        Write-Host "FINISH SMTP"
    }
}

class Config{
    [array]$Paths
    [object]$Smtp
    [int]$DebounceSeconds
    [string]$BaselineFile
    [string]$EventLogFile

    Config($user, $passwrd, $FolderPathList, $FilePathList){
        Write-Host "WRITING CONFIG"
        $this.Paths = ($FolderPathList + $FilePathList)
        $this.Smtp = New-Object Smtp $user, $passwrd
        $this.DebounceSeconds = 2
        $this.BaselineFile = "C:\ProgramData\HIDS\baseline.json"
        $this.EventLogFile = "C:\ProgramData\HIDS\events.log"
        Write-Host "FINISH CONFIG"
    }
}

Function Get-Folder(){
    $FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    [void] $FolderBrowserDialog.ShowDialog()
    $FolderPath = $FolderBrowserDialog.SelectedPath
    $FolderPathList.add($FolderPath)
}

Function Get-File(){
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    [void] $OpenFileDialog.ShowDialog()
    $FilePath = $OpenFileDialog.FileName
    $FilePathList.add($FilePath)
}

$Form                            = New-Object system.Windows.Forms.Form
$Form.ClientSize                 = New-Object System.Drawing.Point(400,492)
$Form.text                       = "SurveyorSetup"
$Form.TopMost                    = $false

$Button1                         = New-Object system.Windows.Forms.Button
$Button1.text                    = "Add File"
$Button1.width                   = 80
$Button1.height                  = 30
$Button1.location                = New-Object System.Drawing.Point(149,108)
$Button1.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Button2                         = New-Object system.Windows.Forms.Button
$Button2.text                    = "Add Folder"
$Button2.width                   = 81
$Button2.height                  = 30
$Button2.location                = New-Object System.Drawing.Point(149,109)
$Button2.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Label1                          = New-Object system.Windows.Forms.Label
$Label1.text                     = "email"
$Label1.AutoSize                 = $true
$Label1.width                    = 25
$Label1.height                   = 10
$Label1.location                 = New-Object System.Drawing.Point(11,27)
$Label1.Font                     = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$TextBox1                        = New-Object system.Windows.Forms.TextBox
$TextBox1.multiline              = $false
$TextBox1.width                  = 261
$TextBox1.height                 = 20
$TextBox1.location               = New-Object System.Drawing.Point(89,24)
$TextBox1.Font                   = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Groupbox1                       = New-Object system.Windows.Forms.Groupbox
$Groupbox1.height                = 93
$Groupbox1.width                 = 373
$Groupbox1.text                  = "Email Setup"
$Groupbox1.location              = New-Object System.Drawing.Point(12,12)

$Label2                          = New-Object system.Windows.Forms.Label
$Label2.text                     = "password"
$Label2.AutoSize                 = $true
$Label2.width                    = 25
$Label2.height                   = 10
$Label2.location                 = New-Object System.Drawing.Point(11,53)
$Label2.Font                     = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Groupbox2                       = New-Object system.Windows.Forms.Groupbox
$Groupbox2.height                = 150
$Groupbox2.width                 = 372
$Groupbox2.text                  = "Folders Setup"
$Groupbox2.location              = New-Object System.Drawing.Point(12,123)

$Groupbox3                       = New-Object system.Windows.Forms.Groupbox
$Groupbox3.height                = 147
$Groupbox3.width                 = 372
$Groupbox3.text                  = "File Setup"
$Groupbox3.location              = New-Object System.Drawing.Point(12,291)

$ListView1                       = New-Object system.Windows.Forms.ListView
$ListView1.text                  = "listView"
$ListView1.width                 = 352
$ListView1.height                = 83
$ListView1.location              = New-Object System.Drawing.Point(10,15)

$ListView2                       = New-Object system.Windows.Forms.ListView
$ListView2.text                  = "listView"
$ListView2.width                 = 352
$ListView2.height                = 81
$ListView2.location              = New-Object System.Drawing.Point(11,17)

$Button3                         = New-Object system.Windows.Forms.Button
$Button3.text                    = "Save Configuration"
$Button3.width                   = 133
$Button3.height                  = 30
$Button3.location                = New-Object System.Drawing.Point(136,449)
$Button3.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$TextBox2                        = New-Object system.Windows.Forms.TextBox
$TextBox2.multiline              = $false
$TextBox2.width                  = 261
$TextBox2.height                 = 20
$TextBox2.location               = New-Object System.Drawing.Point(89,49)
$TextBox2.Font                   = New-Object System.Drawing.Font('Microsoft Sans Serif',10)
$TextBox2.PasswordChar           = '*';

$Groupbox3.controls.AddRange(@($Button1,$ListView2))
$Groupbox2.controls.AddRange(@($Button2,$ListView1))
$Groupbox1.controls.AddRange(@($Label1,$TextBox1,$Label2,$TextBox2))
$Form.controls.AddRange(@($Groupbox1,$Groupbox2,$Groupbox3,$Button3))

$Button1.Add_Click({ Get-File; AddFilePath })
$Button2.Add_Click({ Get-Folder; AddFolderPath })
$Button3.Add_Click({ MakeJSON })

Function AddFilePath(){
    $ListView2.Items.Clear()
    foreach($path in $FilePathList){
        $ListView2.Items.Add($path)
    }
}

Function AddFolderPath(){
    $ListView1.Items.Clear()
    foreach($path in $FolderPathList){
        $ListView1.Items.Add($path)
    }
}

Function MakeJSON(){
    $password = (ConvertTo-SecureString -AsPlainText -Force $TextBox2.Text | ConvertFrom-SecureString)
    New-Object Config $TextBox1.Text, $password, $FolderPathList, $FilePathList | ConvertTo-Json | Out-File -FilePath .\CONFIG_NEW.json
    $Form.close()
}

[void]$Form.ShowDialog()