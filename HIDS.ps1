#Classe de soutien pour créer les entrées de la baseline des fichiers observés
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

#Récupération des paramètres de configuration
$CONFIG = ConvertFrom-Json (Get-Content -Raw "C:\Program Files (x86)\HIDS\config.json")

#Fonction de soutien pour ajouter des informations à log
function Log-Event ($Message){
    $ts = (Get-Date).ToString("s")
    $out = "[$ts] $Message"
    $out | Out-File -FilePath $CONFIG.EventLogFile -Append -Encoding UTF8 #Ajout d'un log au fichier correspondant
    Write-Host $out #Ecriture du log dans la console
}

Log-Event("HIDS demarre")

#Hashtable de stockage des baseline
$Baseline = @{}

#Fonction de soutien pour ajouter tous les paths de fichiers à l'objet de baseline
Function addToBaseline($List){
    foreach ($Path in $List){
        $temp = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if($temp){ #Si le path existe uniquement
            if($temp.PSIsContainer){ #Si le path indique un dossier
                $children = Get-ChildItem -LiteralPath $temp | Select-Object -ExpandProperty FullName #Trouver les éléments enfants du dossier
                addToBaseline($children) #Appel récursif pour examiner le contenu du dossier
            }
            else{
                $nieuw = New-Object FileBaseline($temp) #Création d'un objet baseline pour un fichier
                $Baseline[$Path] = $nieuw #Ajout de l'objet baseline dans la Hashtable de stockage
            }
        }
    }
}

#Appel de la fonction d'ajout de baseline pour tous les paths présents dans les paramètres
addToBaseline($CONFIG.Paths)

#Export de la baseline des fichiers
#Pas nécesssaire en l'état et pas particulièrement sécurisé
#ConvertTo-Json $Baseline | Out-File -FilePath "C:\Program Files (x86)\HIDS\baseline.json"

#Variables de soutien pour l'établissement du système d'alertes
$watchers = @()
$subs = @()
$RunId = (Get-Date).ToString('yyyyMMddHHmmssfff')

$i=0;
#Lancement de l'observation de chaque fichier/dossier
foreach ( $path in $CONFIG.Paths ) {
    $fsw = New-Object System.IO.FileSystemWatcher

    if ((Get-Item $path).PSIsContainer) { #Si le path indique un dossier
        $fsw.Path = $path
        $fsw.Filter = "*" #Sélectionner tous les enfants du dossier
        $fsw.IncludeSubdirectories = $true
    } else {#Si le path indique un fichier
        $fsw.Path = Split-Path $path -Parent
        $fsw.Filter = Split-Path $path -Leaf #Sélectionner le fichier uniquement
        $fsw.IncludeSubdirectories = $false
    }
    #Attributs à retourner en cas d'évènement détecté
    $fsw.NotifyFilter       = [System.IO.NotifyFilters]"FileName, DirectoryName, LastWrite, Size, CreationTime, Attributes"
    $fsw.InternalBufferSize = 65536

    $idBase = "HIDS.$RunId.$i"

    #Ajout de chacune des possibilités d'évènement: Modifié, Crée, Supprimé, Renommé, Erreur
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

#Fonction de soutien pour l'envoi de mails d'alerte
function Send-Email($Subject, $Body) {
    $confSmtp = $CONFIG.Smtp

    try {
        #Paramétrage de l'objet d'envoi de mail avec les paramètres de configuration
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = [System.Net.Mail.MailAddress]$confSmtp.From #Ajout de l'addresse mail d'envoi

        #Ajout des addresses mail receptrices
        foreach($to in $CONFIG.Receivers){
            $null = $mail.To.Add([System.Net.Mail.MailAddress]$to)
        }

        $mail.Subject = $Subject #Ajout de l'objet du mail
        $mail.Body = $Body #Ajout du contenu du mail
        $mail.IsBodyHtml = $false
        $mail.BodyEncoding = [System.Text.Encoding]::UTF8
        $mail.SubjectEncoding = [System.Text.Encoding]::UTF8

        $smtp = New-Object System.Net.Mail.SmtpClient($confSmtp.Server,$confSmtp.Port)
        $smtp.DeliveryMethod = [System.Net.Mail.SmtpDeliveryMethod]::Network
        $smtp.EnableSsl = $confSmtp.UseTls
        $smtp.UseDefaultCredentials = $false

        $SecurePassword = ConvertTo-SecureString $confSmtp.Password
        $smtp.Credentials = New-Object System.Net.NetworkCredential($confSmtp.Username, $SecurePassword)

        $smtp.TargetName = 'STARTTLS/' + $confSmtp.Server #Ajout du serveur TLS d'envoi

        $smtp.Send($mail) #Envoi du mail
        $true
    } catch {
        Log-Event("Envoi mail echoue : $($_.Exception.Message)")
        $false
    }
}

#Hashtable pour mettre en place le temps de debounce
$LastEventTime = @{}
#Fonction de soutien pour gérer un évènement sur un fichier
function Handle-Event($Evnt) {
    $Arguments = $Evnt.SourceEventArgs
    $ename = $Evnt.EventName

    if ($ename -eq 'Error') { #Si l'évènement est une erreure
        Log-Event("Watcher ERROR : " + $Arguments.GetException().Message)
        return #Ne pas effectuer plus d'actions
    }

    $path = $Arguments.FullPath
    
    if ($LastEventTime.ContainsKey($path)) { #Si un évènement à déjà eu lieu sur le fichier en question
        if (((Get-Date) - $LastEventTime[$path]).TotalSeconds -lt $CONFIG.DebounceSeconds) { #Si le temps de debounce ne s'est pas écoulé
            return #Ne pas effectuer plus d'actions
        }
    }
    #Inscription d'un évènement sur le fichier en question
    $LastEventTime[$path] = (Get-Date)
    
    Log-Event("[EVENT] $ename -> $path")

    $exists = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    $currentHash = $null
    if ($exists) { #Si le fichier existe
        #Calcul du nouveau hash actuel
        $currentHash = (Get-FileHash -Path $path -Algorithm SHA256).Hash
    }

    $hash = $null
    if($Baseline.ContainsKey($path)){ #Si le fichier est inclut dans la baseline
        #Récupération du hash de base du fichier
        $hash = $Baseline[$path].Hash
    }

    #Variable à utiliser pour créer le mail d'alerte
    $subject = $null
    $body = $null

    if (-not $exists -or $ename -eq "Deleted") { #Si le fichier n'existe pas ou si il a été supprimé
        $subject = "[HIDS] Suppression: $path"
        $body = "Suppression detectee sur $(hostname)`nPath: $path`nBaselineHash: $hash"
        Log-Event("Suppression detectee: " + $path)
    }
    elseif ($null -eq $hash -and $ename -in @('Created','Renamed','Changed')) { #Si le fichier n'est pas dans la baseline et si il a été: Crée, Renommé ou Modifié
        $subject = "[HIDS] Creation: $path"
        $body = "Creation detectee sur $(hostname)`nPath: $path`nCurrentHash: $currentHash`nType: $ename"
        Log-Event("Creation detectee (hors baseline): " + $path + " (current=" + $currentHash + ")")
    }
    elseif ($hash -ne $currentHash) { #Si le hash récupéré est différent du hash d'origine
        $subject = "[HIDS] Modification: $path"
        $body = "Modification detectee sur $(hostname)`nPath: $path`nBaselineHash: $hash`nCurrentHash: $currentHash`nType: $ename"
        Log-Event("Modification detectee: " + $path + " (baseline=" + $hash + " / current=" + $currentHash + ")")
    }
    else { #Si le hash récupéré correspond au hash d'origine
        Log-Event("Evenement non critique (hash identique): " + $path + " (" + $ename + ")")
    }

    if ($subject) { #Si un mail doit être envoyé
        $mail = Send-Email $subject $body
        if ($mail) { #Si le mail a été correctement envoyé
            Log-Event("Mail envoye: " + $path)
        }
        else {
            Log-Event("Echec envoi mail: " + $path)
        }
    }
}

try {
    while ($true) { #Boucle principale d'attente d'un évènement
        $evnt = Wait-Event -SourceIdentifier "HIDS.*" -Timeout 5
        if ($evnt) { #Si un évènement a été détecté
            Handle-Event($evnt) #Gestion de l'évènement
            Remove-Event -EventIdentifier $evnt.EventIdentifier #Suppression de l'évènement puisque déjà géré
        }
    }
}
finally { #Etapes de nettoyage à l'arrêt de l'HIDS
    foreach ($s in $subs) { #Désactiver tous les observateurs
        Unregister-Event -SourceIdentifier $s.SourceIdentifier -ErrorAction SilentlyContinue
    }
    foreach ($w in $watchers) { #Désactiver tous les observateurs
        $w.EnableRaisingEvents = $false
        $w.Dispose()
    }
    Get-Event | Remove-Event -ErrorAction SilentlyContinue #Supprimer tous les évènements
    Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like 'HIDS*' } | Unregister-Event -Force -ErrorAction SilentlyContinue
    Log-Event("HIDS arrete")
}
