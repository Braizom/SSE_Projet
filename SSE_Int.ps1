Function Get-Folder(){
    [void] [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    $FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    [void] $FolderBrowserDialog.ShowDialog()
    return $FolderBrowserDialog.SelectedPath
}

Function Get-File(){
    [void] [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    [void] $OpenFileDialog.ShowDialog()
    return $OpenFileDialog.FileName
}


Function Show-Menu(){
    $menuOptions = @(
        '1: Select Folder'
        '2: Select File'
    )

    foreach ($option in $menuOptions) {
        Write-Host $option
    }

    switch (Read-Host 'Please select an option (1-2)') {
        '1' { return Get-Folder }
        '2' { return Get-File }
        default { Write-Host 'Invalid choice. Please try again.'; return Show-Menu }
    }
}

Show-Menu