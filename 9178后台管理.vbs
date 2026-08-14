' 9178gg 后台管理系统 - 静默启动器（不弹命令行黑窗）
' 双击用系统默认浏览器打开 J:\9178GG\admin.html
Option Explicit
Dim sh, fso, targetPath, currentDir, url

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' 目标 admin.html：优先用当前脚本所在目录的 admin.html，找不到就用绝对路径 J:\9178GG\admin.html
currentDir = fso.GetParentFolderName(WScript.ScriptFullName)
targetPath = fso.BuildPath(currentDir, "admin.html")
If Not fso.FileExists(targetPath) Then targetPath = "J:\9178GG\admin.html"

' 转成 file:/// 协议 URL，带 file:// 前缀能确保交给默认浏览器处理
url = "file:///" & Replace(targetPath, "\", "/")

On Error Resume Next
sh.Run url, 1, False
If Err.Number <> 0 Then
    ' 失败就退化成直接用 ShellExecute 打开文件
    sh.Run """" & targetPath & """", 1, False
End If
On Error GoTo 0

Set sh = Nothing
Set fso = Nothing
