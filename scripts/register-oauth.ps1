param([string]$Executable = "$PSScriptRoot\..\build\windows\x64\runner\Release\mynotes.exe")
$resolved = (Resolve-Path -LiteralPath $Executable -ErrorAction Stop).Path
$key = 'HKCU:\Software\Classes\com.hoang.mynotes'
if (Test-Path -LiteralPath $key) {
  throw 'Protocol already registered. Review existing registration before replacing.'
}
New-Item -Path $key -Force | Out-Null
Set-Item -LiteralPath $key -Value 'URL:MyNotes OAuth'
New-ItemProperty -LiteralPath $key -Name 'URL Protocol' -Value '' -PropertyType String | Out-Null
New-Item -Path "$key\shell\open\command" -Force | Out-Null
Set-Item -LiteralPath "$key\shell\open\command" -Value ('"' + $resolved + '" "%1"')
