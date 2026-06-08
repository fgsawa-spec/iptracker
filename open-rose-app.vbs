Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(scriptDir, "OpenRoseGui.ps1")
command = "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & ps1 & Chr(34)
shell.Run command, 0, False
