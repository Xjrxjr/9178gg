' 9178GG - 用记事本打开 pat.js（如果没有就从 pat.example.js 复制一份）
' 这是给不想用命令行、只想手动粘贴 PAT 到记事本的人。
Option Explicit

Dim sh, fso, thisDir, patPath, examplePath
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

thisDir     = fso.GetParentFolderName(WScript.ScriptFullName)
patPath     = fso.BuildPath(thisDir, "pat.js")
examplePath = fso.BuildPath(thisDir, "pat.example.js")

If Not fso.FileExists(patPath) Then
    If fso.FileExists(examplePath) Then
        fso.CopyFile examplePath, patPath, False
        MsgBox "已从 pat.example.js 自动复制出一份 pat.js（没内容的空模板）。" & vbCrLf & _
               "现在记事本会打开它 → 找到最后一行：" & vbCrLf & vbCrLf & _
               "    window._GH_PAT = '';" & vbCrLf & vbCrLf & _
               "把你的 PAT 粘贴到两个单引号中间，保存记事本，再打开 admin.html 就自动读了。", _
               vbInformation Or vbSystemModal, "3-记事本编辑PAT"
    Else
        ' 连模板都没，直接新建空的
        Dim ts
        Set ts = fso.CreateTextFile(patPath, True, False)
        ts.WriteLine "window._GH_PAT = '';"
        ts.Close
        Set ts = Nothing
    End If
Else
    MsgBox "pat.js 已经存在，现在用记事本打开它。" & vbCrLf & vbCrLf & _
           "找到最后一行 window._GH_PAT = '...' 把里面的字符串换成你的真实 PAT，" & vbCrLf & _
           "然后记事本→保存（Ctrl+S）→关掉记事本→刷新 admin.html 即可。", _
           vbInformation Or vbSystemModal, "3-记事本编辑PAT"
End If

On Error Resume Next
sh.Run "notepad.exe """ & patPath & """", 1, False
If Err.Number <> 0 Then
    ' notepad 失败就用系统默认打开方式
    sh.Run """" & patPath & """", 1, False
End If
On Error GoTo 0

Set sh = Nothing
Set fso = Nothing
