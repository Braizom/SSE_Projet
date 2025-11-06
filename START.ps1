Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$FolderPathList = [System.Collections.ArrayList]@()
$FilePathList = [System.Collections.ArrayList]@()
$ReceiverList = [System.Collections.ArrayList]@()

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

    Smtp($user, $passwrd, $To){
        $this.Server = FindSmtp($user)
        $this.Port = 587
        $this.UseTls = $true
        $this.From = $user
        $this.To = $To
        $this.Username = $user
        $this.Password = $passwrd
    }
}

class Config{
    [array]$Receivers
    [array]$Paths
    [object]$Smtp
    [int]$DebounceSeconds
    [string]$BaselineFile
    [string]$EventLogFile

    Config($user, $passwrd, $FolderPathList, $FilePathList, $ReceiverList){
        $this.Receivers = $ReceiverList
        $this.Paths = ($FolderPathList + $FilePathList)
        $this.Smtp = New-Object Smtp $user, $passwrd, $ReceiverList[0]
        $this.DebounceSeconds = 2
        $this.BaselineFile = "C:\Program Files (x86)\HIDS\baseline.json"
        $this.EventLogFile = "C:\Program Files (x86)\HIDS\events.log"
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
$Button1.location                = New-Object System.Drawing.Point(145,84)
$Button1.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Button2                         = New-Object system.Windows.Forms.Button
$Button2.text                    = "Add Folder"
$Button2.width                   = 81
$Button2.height                  = 30
$Button2.location                = New-Object System.Drawing.Point(148,75)
$Button2.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Label1                          = New-Object system.Windows.Forms.Label
$Label1.text                     = "sender"
$Label1.AutoSize                 = $true
$Label1.width                    = 25
$Label1.height                   = 10
$Label1.location                 = New-Object System.Drawing.Point(11,27)
$Label1.Font                     = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$TextBox1                        = New-Object system.Windows.Forms.TextBox
$TextBox1.multiline              = $false
$TextBox1.width                  = 279
$TextBox1.height                 = 20
$TextBox1.location               = New-Object System.Drawing.Point(80,24)
$TextBox1.Font                   = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Groupbox1                       = New-Object system.Windows.Forms.Groupbox
$Groupbox1.height                = 151
$Groupbox1.width                 = 373
$Groupbox1.text                  = "Email Setup"
$Groupbox1.location              = New-Object System.Drawing.Point(12,12)

$Label2                          = New-Object system.Windows.Forms.Label
$Label2.text                     = "password"
$Label2.AutoSize                 = $true
$Label2.width                    = 25
$Label2.height                   = 10
$Label2.location                 = New-Object System.Drawing.Point(11,57)
$Label2.Font                     = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Groupbox2                       = New-Object system.Windows.Forms.Groupbox
$Groupbox2.height                = 114
$Groupbox2.width                 = 372
$Groupbox2.text                  = "Folders Setup"
$Groupbox2.location              = New-Object System.Drawing.Point(13,188)

$Groupbox3                       = New-Object system.Windows.Forms.Groupbox
$Groupbox3.height                = 127
$Groupbox3.width                 = 372
$Groupbox3.text                  = "File Setup"
$Groupbox3.location              = New-Object System.Drawing.Point(13,316)

$ListView1                       = New-Object system.Windows.Forms.ListView
$ListView1.text                  = "listView"
$ListView1.width                 = 352
$ListView1.height                = 49
$ListView1.location              = New-Object System.Drawing.Point(10,18)

$ListView2                       = New-Object system.Windows.Forms.ListView
$ListView2.text                  = "listView"
$ListView2.width                 = 352
$ListView2.height                = 52
$ListView2.location              = New-Object System.Drawing.Point(11,17)

$TextBox2                        = New-Object system.Windows.Forms.TextBox
$TextBox2.multiline              = $false
$TextBox2.width                  = 278
$TextBox2.height                 = 20
$TextBox2.location               = New-Object System.Drawing.Point(80,53)
$TextBox2.Font                   = New-Object System.Drawing.Font('Microsoft Sans Serif',10)
$TextBox2.PasswordChar           = '*';

$Button3                         = New-Object system.Windows.Forms.Button
$Button3.text                    = "Save Configuration"
$Button3.width                   = 133
$Button3.height                  = 30
$Button3.location                = New-Object System.Drawing.Point(136,449)
$Button3.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$ListView3                       = New-Object system.Windows.Forms.ListView
$ListView3.text                  = "listView"
$ListView3.width                 = 343
$ListView3.height                = 30
$ListView3.location              = New-Object System.Drawing.Point(17,85)

$TextBox3                        = New-Object system.Windows.Forms.TextBox
$TextBox3.multiline              = $false
$TextBox3.width                  = 239
$TextBox3.height                 = 20
$TextBox3.location               = New-Object System.Drawing.Point(122,122)
$TextBox3.Font                   = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Button4                         = New-Object system.Windows.Forms.Button
$Button4.text                    = "Add receiver"
$Button4.width                   = 94
$Button4.height                  = 19
$Button4.location                = New-Object System.Drawing.Point(11,122)
$Button4.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Groupbox3.controls.AddRange(@($Button1,$ListView2))
$Groupbox2.controls.AddRange(@($Button2,$ListView1))
$Groupbox1.controls.AddRange(@($Label1,$TextBox1,$Label2,$TextBox2,$ListView3,$TextBox3,$Button4))
$Form.controls.AddRange(@($Groupbox1,$Groupbox2,$Groupbox3,$Button3))

$Button1.Add_Click({ Get-File; AddFilePath })
$Button2.Add_Click({ Get-Folder; AddFolderPath })
$Button3.Add_Click({ MakeJSON; LaunchHIDS })
$Button4.Add_Click({ Get-Receiver; AddReceiver })

Function Get-Receiver(){
    if($TextBox3.Text -eq ""){
        return
    }
    $ReceiverList.add($TextBox3.Text)
    $TextBox3.Clear()
}

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

Function AddReceiver(){
    $ListView3.Items.Clear()
    foreach($receiver in $ReceiverList){
        $ListView3.Items.Add($receiver)
    }
}

Function MakeJSON(){
    $password = (ConvertTo-SecureString -AsPlainText -Force $TextBox2.Text | ConvertFrom-SecureString)
    New-Object Config $TextBox1.Text, $password, $FolderPathList, $FilePathList, $ReceiverList | ConvertTo-Json | Out-File -FilePath "C:\Program Files (x86)\HIDS\config.json"
    $Form.close()
}

Function LaunchHIDS(){
    #Start-Process powershell.exe -ArgumentList "-file .\HIDS.ps1"
    Start-Process "C:\Program Files (x86)\HIDS\HIDS.exe"
}

[void]$Form.ShowDialog()