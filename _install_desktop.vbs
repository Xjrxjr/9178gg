' 创建桌面和开始菜单快捷方式（直接用 VBS/COM 写，避开 PowerShell 执行策略限制）
Option Explicit
Dim sh, fso, desktop, startMenuFolder, srcVbs, srcUrl, lnk, s, i, tmpVbs, result

Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' 定位目录
desktop = sh.SpecialFolders("Desktop")
On Error Resume Next
startMenuFolder = sh.ExpandEnvironmentStrings("%APPDATA%\Microsoft\Windows\Start Menu\Programs\9178GG")
On Error GoTo 0
If startMenuFolder = "" Or InStr(startMenuFolder, "%") > 0 Then
  startMenuFolder = sh.SpecialFolders("StartMenu") & "\Programs\9178GG"
End If
If Not fso.FolderExists(startMenuFolder) Then On Error Resume Next : fso.CreateFolder startMenuFolder : On Error GoTo 0

srcVbs = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "9178后台管理.vbs")
srcUrl = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "9178后台管理.url")
If Not fso.FileExists(srcVbs) Then srcVbs = "J:\9178GG\9178后台管理.vbs"
If Not fso.FileExists(srcUrl) Then srcUrl = "J:\9178GG\9178后台管理.url"

' 1) 把 .url 和 .vbs 直接复制到桌面（永远可用的兜底）
On Error Resume Next
If fso.FileExists(srcUrl) Then fso.CopyFile srcUrl, desktop & "\9178后台管理.url", True
If fso.FileExists(srcVbs) Then fso.CopyFile srcVbs, desktop & "\9178后台管理.vbs", True
On Error GoTo 0

' 2) 原生 .lnk（指向 .vbs 启动器）— 不会弹黑窗
On Error Resume Next
Set lnk = sh.CreateShortcut(desktop & "\9178后台管理.lnk")
If Err.Number = 0 Then
  lnk.TargetPath       = srcVbs
  lnk.WorkingDirectory = "J:\9178GG"
  lnk.Description      = "9178GG - 后台管理系统"
  lnk.IconLocation     = sh.ExpandEnvironmentStrings("%SystemRoot%\System32\imageres.dll") & ",175"
  lnk.WindowStyle      = 1
  lnk.Save
  If fso.FolderExists(startMenuFolder) Then
    fso.CopyFile desktop & "\9178后台管理.lnk", startMenuFolder & "\9178后台管理.lnk", True
  End If
End If
Err.Clear
On Error GoTo 0

' 3) 兜底：再复制 .url 和 .vbs 到开始菜单，保证至少能找到
On Error Resume Next
If fso.FolderExists(startMenuFolder) Then
  If fso.FileExists(srcUrl) Then fso.CopyFile srcUrl, startMenuFolder & "\9178后台管理.url", True
  If fso.FileExists(srcVbs) Then fso.CopyFile srcVbs, startMenuFolder & "\9178后台管理.vbs", True
End If
On Error GoTo 0

WScript.Echo "Install complete:" & vbCrLf & _
             "  Desktop    : " & desktop & vbCrLf & _
             "  Start Menu : " & startMenuFolder & vbCrLf & vbCrLf & _
             "Look for '9178后台管理' on your desktop / Start button."
Set sh = Nothing
Set fso = Nothing
