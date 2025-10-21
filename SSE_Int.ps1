[void] [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
$FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$FolderBrowserDialog.ShowDialog()