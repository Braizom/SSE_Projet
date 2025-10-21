<#
  HIDS-PoC.ps1 — version stable avec boucle Wait-Event
  - lit config.json
  - baseline SHA-256 (fichier et dossier)
  - FileSystemWatcher par chemin (buffer ↑)
  - EVTS gérés dans la boucle principale via Wait-Event (pas de -Action, pas de Job)
  - pour chaque evt: log -> (re)hash -> comparaisons -> email
  - pas d'auto-rebaseline
#>



# ---------- SETUP ----------
param([switch]$Setup)

if ($Setup) {
  # Relance en STA pour les boîtes de dialogue Windows.Forms
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell -ArgumentList "-STA -File `"$PSCommandPath`" -Setup" -Verb RunAs
    exit
  }

  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.Application]::EnableVisualStyles() | Out-Null

  $cfgPath = Join-Path $PSScriptRoot "config.json"
  if (-not (Test-Path $cfgPath)) {
    [System.Windows.Forms.MessageBox]::Show("config.json introuvable : $cfgPath","HIDS Setup",
      [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
  }
  $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

  $picked = @()

  # 1) Dossiers (tu peux cliquer plusieurs fois ; Annuler pour passer aux fichiers)
  do {
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = "Choisis un dossier à SURVEILLER (Annuler pour passer aux fichiers)"
    if ($fb.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
      $picked += $fb.SelectedPath
    } else { break }
  } while ($true)

  # 2) Fichiers (multi-sélection)
  $of = New-Object System.Windows.Forms.OpenFileDialog
  $of.Title = "Choisis des fichiers à SURVEILLER (multisélection)"
  $of.Multiselect = $true
  $of.Filter = "Tous (*.*)|*.*"
  if ($of.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $picked += $of.FileNames
  }

  # Normaliser, filtrer, dédupliquer
  $picked = $picked |
    Where-Object { $_ -and (Test-Path $_) } |
    ForEach-Object { $_ -replace '\\','/' } |
    Select-Object -Unique

  if (-not $picked -or $picked.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("Aucun chemin sélectionné. Aucune modification apportée.","HIDS Setup",
      [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    exit 0
  }

  # >>> MODE REMPLACEMENT : on écrase complètement la liste Paths <<<
  $cfg.Paths = $picked
  $cfg | ConvertTo-Json -Depth 10 | Out-File $cfgPath -Encoding UTF8

  $preview = ($picked | ForEach-Object { " - $_" }) -join "`r`n"
  [System.Windows.Forms.MessageBox]::Show("config.json MIS À JOUR (liste REMPLACÉE).`r`nChemins surveillés :`r`n$preview","HIDS Setup",
    [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  exit 0
}



# ---------- UTILITAIRES ----------
function Read-Config {
    param([string]$Path = ".\config.json")
    if (-not (Test-Path $Path)) { throw "Fichier config introuvable: $Path" }
    try { Get-Content $Path -Raw | ConvertFrom-Json }
    catch { throw "config.json invalide : $($_.Exception.Message)" }
}

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Log-Event {
    param([string]$Message, [string]$EventFile)
    $ts = (Get-Date).ToString("s")
    Ensure-Directory (Split-Path $EventFile -Parent)
    "[$ts] $Message" | Out-File -FilePath $EventFile -Append -Encoding UTF8
    Write-Host "[$ts] $Message"
}

function Compute-Hash {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $null }
    $it = Get-Item $FilePath -ErrorAction SilentlyContinue
    if ($null -eq $it -or $it.PSIsContainer) { return $null }
    try { (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash }
    catch { Log-Event -Message "Erreur hash '$FilePath' : $($_.Exception.Message)" -EventFile $script:EventLogFile; $null }
}

function Save-Baseline { param($Baseline,[string]$Path)
    Ensure-Directory (Split-Path $Path -Parent)
    $Baseline | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
}

function Load-Baseline {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @{} }
    $raw = Get-Content $Path -Raw | ConvertFrom-Json
    if ($null -eq $raw) { return @{} }
    return Convert-ToHashtableDeep $raw
}

function Convert-ToHashtableDeep {
    param($obj)
    if ($null -eq $obj) { return $null }

    # Déjà une hashtable ?
    if ($obj -is [System.Collections.IDictionary]) {
        $ht = @{}
        foreach ($k in $obj.Keys) { $ht[$k] = Convert-ToHashtableDeep $obj[$k] }
        return $ht
    }

    # Tableau / liste
    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
        $list = @()
        foreach ($item in $obj) { $list += ,(Convert-ToHashtableDeep $item) }
        return $list
    }

    # PSCustomObject -> Hashtable
    if ($obj -is [pscustomobject]) {
        $ht = @{}
        foreach ($p in $obj.PSObject.Properties) { $ht[$p.Name] = Convert-ToHashtableDeep $p.Value }
        return $ht
    }

    # Scalaire
    return $obj
}

function Send-Email {
    param(
        [string]$SmtpServer, [int]$Port, [bool]$UseTls,
        [string]$From, [string]$To,
        [string]$Subject, [string]$Body,
        [string]$User, [string]$Password
    )
    try {
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = [System.Net.Mail.MailAddress]$From
        $null = $mail.To.Add([System.Net.Mail.MailAddress]$To)
        $mail.Subject = $Subject
        $mail.Body = $Body
        $mail.IsBodyHtml = $false
        $mail.BodyEncoding    = [System.Text.Encoding]::UTF8
        $mail.SubjectEncoding = [System.Text.Encoding]::UTF8

        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpServer,$Port)
        $smtp.DeliveryMethod = [System.Net.Mail.SmtpDeliveryMethod]::Network
        $smtp.EnableSsl = $UseTls
        $smtp.UseDefaultCredentials = $false
        if ($User -and $Password) {
            $smtp.Credentials = New-Object System.Net.NetworkCredential($User,$Password)
        } else { throw "Identifiants SMTP manquants." }
        try { $smtp.TargetName = 'STARTTLS/smtp.gmail.com' } catch {}
        $smtp.Send($mail)
        $true
    } catch {
        Log-Event -Message "Envoi mail échoué : $($_.Exception.Message)" -EventFile $script:EventLogFile
        $false
    }
}

# ---------- CONFIG ----------
$Config              = Read-Config
$Paths               = @($Config.Paths)
$Smtp                = $Config.Smtp
$script:EventLogFile = $Config.EventLogFile
$BaselineFile        = $Config.BaselineFile
$DebounceSeconds     = [int]($Config.DebounceSeconds | ForEach-Object { if ($_ -is [int]) {$_} else {2} })

# Nettoyage d’anciens abonnements dans cette session
Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like 'HIDS*' } | Unregister-Event -Force -ErrorAction SilentlyContinue
Ensure-Directory (Split-Path $script:EventLogFile -Parent)
Ensure-Directory (Split-Path $BaselineFile -Parent)
Log-Event -Message "HIDS démarré (heartbeat)" -EventFile $script:EventLogFile

# ---------- BASELINE ----------
$Baseline = Load-Baseline -Path $BaselineFile
if ($Baseline -isnot [hashtable]) { $tmp=@{}; foreach($k in $Baseline.PSObject.Properties.Name){$tmp[$k]=$Baseline.$k}; $Baseline=$tmp }

foreach ($p in $Paths) {
    if (-not $Baseline.ContainsKey($p)) {
        if (Test-Path $p -PathType Leaf) {
            $h = Compute-Hash -FilePath $p
            $Baseline[$p] = @{ Type="File"; Hash=$h; LastSeen=(Get-Date).ToString("s") }
            Log-Event -Message "Baseline ajoutée (fichier) : $p -> $h" -EventFile $script:EventLogFile
        } elseif (Test-Path $p -PathType Container) {
            $Baseline[$p] = @{ Type="Directory"; Files=@{} }
            $files = Get-ChildItem -Path $p -File -Recurse -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $hf = Compute-Hash -FilePath $f.FullName
                $Baseline[$p].Files[$f.FullName] = @{ Hash=$hf; LastSeen=(Get-Date).ToString("s") }
            }
            Log-Event -Message "Baseline ajoutée (dossier) : $p -> $($Baseline[$p].Files.Count) fichiers" -EventFile $script:EventLogFile
        } else {
            Log-Event -Message "Chemin introuvable pour baseline : $p" -EventFile $script:EventLogFile
        }
    }
}
Save-Baseline -Baseline $Baseline -Path $BaselineFile

# ---------- DEBOUNCE MAP ----------
$LastEventTime = @{}

# ---------- WATCHERS + SUBSCRIPTIONS (pas d'-Action) ----------
$watchers = @()
$subs     = @()
$RunId    = (Get-Date).ToString('yyyyMMddHHmmssfff')

$Notify = [System.IO.NotifyFilters]"FileName, DirectoryName, LastWrite, Size, CreationTime, Attributes"

for ($i=0; $i -lt $Paths.Count; $i++) {
    $p = $Paths[$i]
    if (-not (Test-Path $p)) { Log-Event -Message "Chemin introuvable, watcher non créé: $p" -EventFile $script:EventLogFile; continue }

    $fsw = New-Object System.IO.FileSystemWatcher
    if ((Get-Item $p).PSIsContainer) {
        $fsw.Path = $p
        $fsw.Filter = "*"                  # capte les fichiers sans extension
        $fsw.IncludeSubdirectories = $true
    } else {
        $fsw.Path   = Split-Path $p -Parent
        $fsw.Filter = Split-Path $p -Leaf
        $fsw.IncludeSubdirectories = $false
    }
    $fsw.NotifyFilter       = $Notify
    $fsw.InternalBufferSize = 65536

    $idBase = "HIDS.$RunId.$i"

    $subs += Register-ObjectEvent -InputObject $fsw -EventName Changed -SourceIdentifier ($idBase + ".Changed")
    $subs += Register-ObjectEvent -InputObject $fsw -EventName Created -SourceIdentifier ($idBase + ".Created")
    $subs += Register-ObjectEvent -InputObject $fsw -EventName Deleted -SourceIdentifier ($idBase + ".Deleted")
    $subs += Register-ObjectEvent -InputObject $fsw -EventName Renamed -SourceIdentifier ($idBase + ".Renamed")
    $subs += Register-ObjectEvent -InputObject $fsw -EventName Error   -SourceIdentifier ($idBase + ".Error")

    $fsw.EnableRaisingEvents = $true
    $watchers += $fsw
    Write-Host "Watcher démarré sur $($fsw.Path) (Filter=$($fsw.Filter))"
}

Write-Host "PoC HIDS en cours d'exécution. Ctrl+C pour arrêter."

# ---------- TRAITEMENT D’UN EVT ----------
function Handle-Event {
    param($evt)

    $args = $evt.SourceEventArgs
    $ename = $evt.EventName

    if ($ename -eq 'Error') {
        Log-Event -Message ("Watcher ERROR : " + $args.GetException().Message) -EventFile $script:EventLogFile
        return
    }

    # full path (Renamed a OldFullPath aussi, mais on traite le nouveau)
    $full = $args.FullPath

    # Debounce simple par fichier
    $now = Get-Date
    if ($LastEventTime.ContainsKey($full)) {
        if (($now - $LastEventTime[$full]).TotalSeconds -lt $DebounceSeconds) { return }
    }
    $LastEventTime[$full] = $now

    Write-Host "[EVENT] $ename -> $full"
    Log-Event -Message ("Evt reçu: " + $ename + " -> " + $full) -EventFile $script:EventLogFile

    $exists = Test-Path $full
    $currentHash = $null
    if ($exists) { $currentHash = Compute-Hash -FilePath $full }

    # Chercher hash baseline
    $bhash = $null
    foreach ($bk in $Baseline.Keys) {
        $b = $Baseline[$bk]
        if ($b.Type -eq "Directory") {
            if ($b.Files.ContainsKey($full)) { $bhash = $b.Files[$full].Hash }
        } elseif ($bk -eq $full) {
            $bhash = $b.Hash
        }
    }

    $subject = $null; $body = $null

    if (-not $exists -or $ename -eq "Deleted") {
        $subject = "[HIDS] Suppression: $full"
        $body    = "Suppression détectée sur $(hostname)`nChemin: $full`nBaselineHash: $bhash"
        Log-Event -Message ("Suppression détectée: " + $full) -EventFile $script:EventLogFile
    }
    elseif ($bhash -eq $null -and $ename -in @('Created','Renamed','Changed')) {
        $subject = "[HIDS] Création: $full"
        $body    = "Création détectée sur $(hostname)`nChemin: $full`nCurrentHash: $currentHash`nType: $ename"
        Log-Event -Message ("Création détectée (hors baseline): " + $full + " (current=" + $currentHash + ")") -EventFile $script:EventLogFile
    }
    elseif ($bhash -ne $currentHash) {
        $subject = "[HIDS] Modification: $full"
        $body    = "Modification détectée sur $(hostname)`nChemin: $full`nBaselineHash: $bhash`nCurrentHash: $currentHash`nType: $ename"
        Log-Event -Message ("Modification détectée: " + $full + " (baseline=" + $bhash + " / current=" + $currentHash + ")") -EventFile $script:EventLogFile
    }
    else {
        Log-Event -Message ("Evénement non critique (hash identique): " + $full + " (" + $ename + ")") -EventFile $script:EventLogFile
    }

    if ($subject) {
        $ok = Send-Email -SmtpServer $Smtp.Server -Port $Smtp.Port -UseTls $Smtp.UseTls `
              -From $Smtp.From -To $Smtp.To -Subject $subject -Body $body `
              -User $Smtp.Username -Password $Smtp.Password
        if ($ok) { Log-Event -Message ("Mail envoyé: " + $full) -EventFile $script:EventLogFile }
        else     { Log-Event -Message ("Echec envoi mail: " + $full) -EventFile $script:EventLogFile }
    }
}

# ---------- BOUCLE PRINCIPALE (attente & dispatch des évènements) ----------
try {
    while ($true) {
        $evt = Wait-Event -SourceIdentifier "HIDS.*" -Timeout 5
        if ($evt) {
            Handle-Event -evt $evt
            Remove-Event -EventIdentifier $evt.EventIdentifier
        }
    }
}
finally {
    foreach ($s in $subs) { try { Unregister-Event -SourceIdentifier $s.SourceIdentifier -ErrorAction SilentlyContinue } catch {} }
    foreach ($w in $watchers) { try { $w.EnableRaisingEvents = $false; $w.Dispose() } catch {} }
    Get-Event | Remove-Event -ErrorAction SilentlyContinue
    Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like 'HIDS*' } | Unregister-Event -Force -ErrorAction SilentlyContinue
    Write-Host "PoC arrêté proprement."
}
