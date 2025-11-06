class FileBaseline{
    [string]$Name
    [string]$Hash
    [string]$Time

    FileBaseline($Path){
        $this.Name = $Path
        $this.Hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
        $this.Time = (Get-Date).ToString("s")
    }
}

$CONFIG = ConvertFrom-Json (Get-Content -Raw "C:\Program Files (x86)\HIDS\config.json")

function Log-Event ($Message){
    $ts = (Get-Date).ToString("s")
    $out = "[$ts] $Message"
    $out | Out-File -FilePath $CONFIG.EventLogFile -Append -Encoding UTF8
    Write-Host $out
}

Log-Event("HIDS demarre")

$Baseline = @{}

Function addToBaseline($List){
    foreach ($Path in $List){
        $temp = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if($temp){
            if($temp.PSIsContainer){
                $children = Get-ChildItem -LiteralPath $temp | Select-Object -ExpandProperty FullName
                addToBaseline($children)
            }
            else{
                $nieuw = New-Object FileBaseline($temp)
                $Baseline[$Path] = $nieuw
            }
        }
    }
}

addToBaseline($CONFIG.Paths)

ConvertTo-Json $Baseline | Out-File -FilePath "C:\Program Files (x86)\HIDS\baseline.json"

$watchers = @()
$subs = @()
$RunId = (Get-Date).ToString('yyyyMMddHHmmssfff')

$i=0;
foreach ( $path in $CONFIG.Paths ) {
    $fsw = New-Object System.IO.FileSystemWatcher

    if ((Get-Item $path).PSIsContainer) {
        $fsw.Path = $path
        $fsw.Filter = "*"
        $fsw.IncludeSubdirectories = $true
    } else {
        $fsw.Path = Split-Path $path -Parent
        $fsw.Filter = Split-Path $path -Leaf
        $fsw.IncludeSubdirectories = $false
    }
    $fsw.NotifyFilter       = [System.IO.NotifyFilters]"FileName, DirectoryName, LastWrite, Size, CreationTime, Attributes"
    $fsw.InternalBufferSize = 65536

    $idBase = "HIDS.$RunId.$i"

    $subs += Register-ObjectEvent -InputObject $fsw -EventName Changed -SourceIdentifier ($idBase + ".Changed")
    $subs += Register-ObjectEvent -InputObject $fsw -EventName Created -SourceIdentifier ($idBase + ".Created")
    $subs += Register-ObjectEvent -InputObject $fsw -EventName Deleted -SourceIdentifier ($idBase + ".Deleted")
    $subs += Register-ObjectEvent -InputObject $fsw -EventName Renamed -SourceIdentifier ($idBase + ".Renamed")
    $subs += Register-ObjectEvent -InputObject $fsw -EventName Error   -SourceIdentifier ($idBase + ".Error")

    $fsw.EnableRaisingEvents = $true
    $watchers += $fsw

    Log-Event("Watcher demarre sur $($fsw.Path) (Filter=$($fsw.Filter))")
    $i++
}

Log-Event("HIDS en cours d'execution. Ctrl+C pour arreter")

function Send-Email($Subject, $Body) {
    $confSmtp = $CONFIG.Smtp

    try {
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = [System.Net.Mail.MailAddress]$confSmtp.From

        foreach($to in $CONFIG.Receivers){
            $null = $mail.To.Add([System.Net.Mail.MailAddress]$to)
        }

        $mail.Subject = $Subject
        $mail.Body = $Body
        $mail.IsBodyHtml = $false
        $mail.BodyEncoding = [System.Text.Encoding]::UTF8
        $mail.SubjectEncoding = [System.Text.Encoding]::UTF8

        $smtp = New-Object System.Net.Mail.SmtpClient($confSmtp.Server,$confSmtp.Port)
        $smtp.DeliveryMethod = [System.Net.Mail.SmtpDeliveryMethod]::Network
        $smtp.EnableSsl = $confSmtp.UseTls
        $smtp.UseDefaultCredentials = $false

        $SecurePassword = ConvertTo-SecureString $confSmtp.Password
        $smtp.Credentials = New-Object System.Net.NetworkCredential($confSmtp.Username, $SecurePassword)

        $smtp.TargetName = 'STARTTLS/' + $confSmtp.Server

        $smtp.Send($mail)
        $true
    } catch {
        Log-Event("Envoi mail echoue : $($_.Exception.Message)")
        $false
    }
}

$LastEventTime = @{}
function Handle-Event($Evnt) {
    $Arguments = $Evnt.SourceEventArgs
    $ename = $Evnt.EventName

    if ($ename -eq 'Error') {
        Log-Event("Watcher ERROR : " + $Arguments.GetException().Message)
        return
    }

    $path = $Arguments.FullPath
    
    if ($LastEventTime.ContainsKey($path)) {
        if (((Get-Date) - $LastEventTime[$path]).TotalSeconds -lt $CONFIG.DebounceSeconds) { 
            return 
        }
    }
    $LastEventTime[$path] = (Get-Date)
    
    Log-Event("[EVENT] $ename -> $path")

    $exists = Test-Path $path
    $currentHash = $null
    if ($exists) {
        $currentHash = (Get-FileHash -Path $path -Algorithm SHA256).Hash
    }

    $hash = $null
    if($Baseline.ContainsKey($path)){
        $hash = $Baseline[$path].Hash
    }

    $subject = $null
    $body = $null

    if (-not $exists -or $ename -eq "Deleted") {
        $subject = "[HIDS] Suppression: $path"
        $body = "Suppression detectee sur $(hostname)`nPath: $path`nBaselineHash: $hash"
        Log-Event("Suppression detectee: " + $path)
    }
    elseif ($null -eq $hash -and $ename -in @('Created','Renamed','Changed')) {
        $subject = "[HIDS] Creation: $path"
        $body = "Creation detectee sur $(hostname)`nPath: $path`nCurrentHash: $currentHash`nType: $ename"
        Log-Event("Creation detectee (hors baseline): " + $path + " (current=" + $currentHash + ")")
    }
    elseif ($hash -ne $currentHash) {
        $subject = "[HIDS] Modification: $path"
        $body = "Modification detectee sur $(hostname)`nPath: $path`nBaselineHash: $hash`nCurrentHash: $currentHash`nType: $ename"
        Log-Event("Modification detectee: " + $path + " (baseline=" + $hash + " / current=" + $currentHash + ")")
    }
    else {
        Log-Event("Evenement non critique (hash identique): " + $path + " (" + $ename + ")")
    }

    if ($subject) {
        $mail = Send-Email $subject $body
        if ($mail) {
            Log-Event("Mail envoye: " + $path)
        }
        else {
            Log-Event("Echec envoi mail: " + $path)
        }
    }
}

try {
    while ($true) {
        $evnt = Wait-Event -SourceIdentifier "HIDS.*" -Timeout 5
        if ($evnt) {
            Handle-Event($evnt)
            Remove-Event -EventIdentifier $evnt.EventIdentifier
        }
    }
}
finally {
    foreach ($s in $subs) {
        Unregister-Event -SourceIdentifier $s.SourceIdentifier -ErrorAction SilentlyContinue
    }
    foreach ($w in $watchers) {
        $w.EnableRaisingEvents = $false
        $w.Dispose()
    }
    Get-Event | Remove-Event -ErrorAction SilentlyContinue
    Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like 'HIDS*' } | Unregister-Event -Force -ErrorAction SilentlyContinue
    Log-Event("HIDS arrete")
}
