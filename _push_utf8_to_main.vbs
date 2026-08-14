' push_utf8_to_main.vbs — 把本地正确的 UTF-8 文件（index.html / data.json / admin.html）推到 GitHub main 分支
' 用法：双击运行，或 cscript //nologo push_utf8_to_main.vbs
' 需要：用户的 GitHub PAT（classic 带 repo / fine-grained 带 Contents R/W 对 Xjrxjr/9178gg）
' 说明：如果浏览器 localStorage 里存过 PAT，也会自动尝试调用 admin.html 里的相同逻辑（此脚本直接 PUT GitHub API）。

Option Explicit

Dim fso, sh, args, pat, owner, repo, branch, files
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

owner  = "Xjrxjr"
repo   = "9178gg"
branch = "main"

files = Array("index.html","data.json","admin.html")

pat = WScript.Arguments.Named("pat")
If pat = "" Then
  ' 优先尝试读项目目录中 _pat.txt
  Dim patTxt, patJs, patBat, line
  patTxt = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "_pat.txt")
  If fso.FileExists(patTxt) Then
    On Error Resume Next
    With fso.OpenTextFile(patTxt, 1, False)
      If Not .AtEndOfStream Then pat = Trim(.ReadLine)
      .Close
    End With
    On Error GoTo 0
  End If
  ' 兜底：弹窗输入
  If pat = "" Then
    pat = InputBox("请输入 GitHub PAT（ghp_ 开头，classic token 需勾选 repo；fine-grained 需对 Xjrxjr/9178gg 有 Contents R/W）" & vbCrLf & vbCrLf & _
                   "提示：PAT 会临时存在 _pat.txt（可选，用完可删），请确保网络通畅。" & vbCrLf & vbCrLf & _
                   "取消 = 取消上传", "Push UTF-8 files to GitHub", "")
    If pat = "" Then WScript.Quit 1
  End If
End If

' 写入 _pat.txt 方便下次使用
On Error Resume Next
With fso.CreateTextFile(fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "_pat.txt"), True, False)
  .Write pat
  .Close
End With
On Error GoTo 0

Dim baseDir, i, filePath, out
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)

out = "Target: https://github.com/" & owner & "/" & repo & " (branch: " & branch & ")" & vbCrLf
For i = 0 To UBound(files)
  filePath = fso.BuildPath(baseDir, files(i))
  If fso.FileExists(filePath) Then
    out = out & vbCrLf & "  [OK] " & files(i) & " (" & fso.GetFile(filePath).Size & " bytes)"
  Else
    out = out & vbCrLf & "  [MISSING] " & files(i)
  End If
Next
out = out & vbCrLf & vbCrLf & "开始上传？（点取消中止）"
If MsgBox(out, vbYesNo + vbQuestion, "Push UTF-8 to GitHub") <> vbYes Then WScript.Quit 2

' ================= 上传逻辑：先 GET /contents/path?ref=main 拿 sha，再 PUT（base64 内容） =================
Dim xhr, fileBytes, b64, path, sha, getUrl, putUrl, payload, status, respText
Set xhr = CreateObject("MSXML2.ServerXMLHTTP.6.0")

' base64 编码函数（借用 ADODB.Stream + XML DOM）
Function FileToBase64(ByVal p)
  Dim stream, dom, el
  Set stream = CreateObject("ADODB.Stream")
  stream.Type = 1 ' adTypeBinary
  stream.Open
  stream.LoadFromFile p
  Set dom = CreateObject("MSXML2.DOMDocument.6.0")
  Set el = dom.CreateElement("b64")
  el.DataType = "bin.base64"
  el.NodeTypedValue = stream.Read
  stream.Close
  FileToBase64 = el.Text
  Set stream = Nothing
  Set el = Nothing
  Set dom = Nothing
End Function

Function ApiCall(method, url, body, optHeaders, outStatus, outText)
  Dim h
  On Error Resume Next
  xhr.Open method, url, False
  For Each h In optHeaders
    If IsArray(optHeaders(h)) Then
      Dim k
      For Each k In optHeaders(h)
        xhr.SetRequestHeader CStr(h), CStr(k)
      Next
    Else
      xhr.SetRequestHeader CStr(h), CStr(optHeaders(h))
    End If
  Next
  If method = "PUT" Or method = "POST" Then
    xhr.Send body
  Else
    xhr.Send
  End If
  If Err.Number <> 0 Then
    outStatus = -1
    outText = "Network error: " & Err.Description
    ApiCall = False
  Else
    outStatus = xhr.Status
    outText = xhr.ResponseText
    ApiCall = (outStatus >= 200 And outStatus < 300)
  End If
  On Error GoTo 0
End Function

Dim commonHeaders, putHeaders, result, okAll, summary, saveMsg, commit
okAll = True
summary = ""
' 提交信息：带时间戳
commit = "修复乱码: UTF-8 重写 index.html/data.json/admin.html + 加载兜底乱码还原 (" & Day(Now) & "/" & Month(Now) & " " & Hour(Now) & ":" & Minute(Now) & ")"

Set commonHeaders = CreateObject("Scripting.Dictionary")
commonHeaders.Add "Accept", "application/vnd.github+json"
commonHeaders.Add "Authorization", "Bearer " & pat
commonHeaders.Add "X-GitHub-Api-Version", "2022-11-28"

Set putHeaders = CreateObject("Scripting.Dictionary")
putHeaders.Add "Accept", "application/vnd.github+json"
putHeaders.Add "Authorization", "Bearer " & pat
putHeaders.Add "X-GitHub-Api-Version", "2022-11-28"
putHeaders.Add "Content-Type", "application/json"

For i = 0 To UBound(files)
  filePath = fso.BuildPath(baseDir, files(i))
  If Not fso.FileExists(filePath) Then
    summary = summary & vbCrLf & "  ❌ " & files(i) & " skipped (missing)"
    okAll = False
  Else
    path = files(i)
    getUrl = "https://api.github.com/repos/" & owner & "/" & repo & "/contents/" & path & "?ref=" & branch
    putUrl = "https://api.github.com/repos/" & owner & "/" & repo & "/contents/" & path

    ' 1. 读 sha
    sha = ""
    result = ApiCall("GET", getUrl, Empty, commonHeaders, status, respText)
    If status = 200 Then
      Dim re, mc, m
      ' 用简单的正则从响应 JSON 中提取 "sha": "xxxx"
      Set re = New RegExp
      re.Pattern = """sha""\s*:\s*""([^""]+)"""
      re.IgnoreCase = True
      re.Global = False
      If re.Test(respText) Then
        Set mc = re.Execute(respText)
        sha = mc(0).SubMatches(0)
      End If
      Set re = Nothing
    ElseIf status = 404 Then
      sha = "" ' 新文件
    Else
      summary = summary & vbCrLf & "  ❌ " & files(i) & " GET sha 失败: HTTP " & status & " " & Left(respText, 160)
      okAll = False
      GoTo NextFile
    End If

    ' 2. 编码 base64（ADODB 直接读文件字节，不做任何编码转换）
    On Error Resume Next
    b64 = FileToBase64(filePath)
    If Err.Number <> 0 Or Len(b64) < 10 Then
      summary = summary & vbCrLf & "  ❌ " & files(i) & " base64 编码失败"
      okAll = False
      On Error GoTo 0
      GoTo NextFile
    End If
    On Error GoTo 0

    ' 3. PUT 写回
    saveMsg = commit & " - " & files(i)
    payload = "{""message"":""" & JsonEscape(saveMsg) & """,""content"":""" & JsonEscape(b64) & """,""branch"":""" & branch & """"
    If sha <> "" Then payload = payload & ",""sha"":""" & sha & """"
    payload = payload & "}"

    result = ApiCall("PUT", putUrl, payload, putHeaders, status, respText)
    If result Then
      summary = summary & vbCrLf & "  ✅ " & files(i) & " 已上传 (HTTP " & status & ")"
    Else
      summary = summary & vbCrLf & "  ❌ " & files(i) & " 上传失败: HTTP " & status & vbCrLf & "       " & Left(respText, 260)
      okAll = False
    End If
  End If
NextFile:
Next

WScript.Echo IIf(okAll, "✅ 全部上传成功!", "⚠️ 部分文件失败") & vbCrLf & vbCrLf & summary

' 简易 JSON 字符串转义
Function JsonEscape(s)
  s = Replace(s, "\", "\\")
  s = Replace(s, """", "\""")
  s = Replace(s, vbCr, "\r")
  s = Replace(s, vbLf, "\n")
  s = Replace(s, vbTab, "\t")
  JsonEscape = s
End Function
