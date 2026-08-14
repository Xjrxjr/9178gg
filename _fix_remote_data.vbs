' fix_remote_data.vbs — 修复 remote_data.json 的双重 UTF-8 损坏并保存为 UTF-8(无 BOM) + JSON.stringify 规整
' 用法: cscript //nologo fix_remote_data.vbs  (也可直接双击)
Option Explicit
Dim fso, sh, inBytes, sIn, sFixed, bytesFixed, outPath
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

Dim baseDir : baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
Dim inPath  : inPath  = fso.BuildPath(baseDir, "remote_data.json")
outPath     = fso.BuildPath(baseDir, "data_fixed.json")

If Not fso.FileExists(inPath) Then
  WScript.Echo "[ERROR] 找不到 J:\9178GG\remote_data.json，请先运行 curl 下载线上 data.json。"
  WScript.Quit 1
End If

' 1) 读输入（作为 bytes）
inBytes = ReadAllBytes(inPath)

' 2) 把整个 bytes 按 UTF-8 解码 -> 得到损坏文本（例如 "è­¦å·ï¼..."）
sIn = BytesToTextUTF8(inBytes)

' 3) 把损坏文本中的 U+0080..U+00FF 字符当作 Latin-1 码点，还原为原始字节数组，再用 UTF-8 解码 -> 恢复正确中文
sFixed = FixDoubleUTF8(sIn)

' 4) JSON.parse + JSON.stringify(2 spaces) 规整格式
Dim json
If EvalJson(sFixed, json) Then
  sFixed = JSONStringify(json, 2)
  WScript.Echo "JSON.parse 成功，共 " & (UBound(json) + 1) & " 条记录，已格式化。"
Else
  WScript.Echo "[WARN] JSON.parse 失败（保留修复后的文本，未格式化），请检查 data.json 语法。"
End If

' 5) 保存为 UTF-8 无 BOM
WriteTextUTF8NoBom outPath, sFixed
WScript.Echo "已保存修复后的文件：" & outPath
WScript.Echo "下一步：把 data_fixed.json 重命名为 data.json 并上传到 GitHub main 分支（或直接用后台/admin.html 保存，或用 _push_utf8_to_main.vbs 批量推）。"

' ========== Helpers ==========
Function ReadAllBytes(p)
  Dim stream
  Set stream = CreateObject("ADODB.Stream")
  stream.Type = 1 : stream.Open : stream.LoadFromFile p
  ReadAllBytes = stream.Read : stream.Close : Set stream = Nothing
End Function

Sub WriteAllBytes(p, b)
  Dim stream
  Set stream = CreateObject("ADODB.Stream")
  stream.Type = 1 : stream.Open : stream.Write b : stream.SaveToFile p, 2
  stream.Close : Set stream = Nothing
End Sub

Function BytesToTextUTF8(b)
  Dim stream
  Set stream = CreateObject("ADODB.Stream")
  stream.Type = 1 : stream.Open : stream.Write b : stream.Position = 0
  stream.Type = 2 : stream.Charset = "UTF-8"
  BytesToTextUTF8 = stream.ReadText(-1)
  stream.Close : Set stream = Nothing
End Function

Sub WriteTextUTF8NoBom(p, text)
  Dim streamUTF8, bom(2), i
  Set streamUTF8 = CreateObject("ADODB.Stream")
  streamUTF8.Type = 2 : streamUTF8.Charset = "UTF-8" : streamUTF8.Open
  streamUTF8.WriteText text
  streamUTF8.Position = 0
  streamUTF8.Type = 1
  ' ADODB.Stream (UTF-8) 会自动加 EF BB BF 3个字节的 BOM，需要截取掉。
  streamUTF8.Position = 3
  Dim noBom
  noBom = streamUTF8.Read(-1)
  streamUTF8.Close
  WriteAllBytes p, noBom
  Set streamUTF8 = Nothing
End Sub

' 修复逻辑：逐字符扫描，所有字符码点<256 的部分按 Latin-1 还原为字节流；
' 字节流再用 UTF-8 解码得到正确中文；遇到码点>255（ASCII 汉字等）直接保留。
Function FixDoubleUTF8(ByVal s)
  If s = "" Then FixDoubleUTF8 = s : Exit Function
  Dim i, ch, cp, bytes(), n, out, decoder, k, chunk
  n = Len(s)
  ReDim bytes(n - 1)
  out = ""
  k = 0
  For i = 1 To n
    ch = Mid(s, i, 1)
    cp = AscW(ch)
    If cp < 0 Then cp = cp + 65536
    If cp <= 255 Then
      bytes(k) = CByte(cp And &HFF)
      k = k + 1
    Else
      ' 遇到非 Latin-1 字符（如 ASCII 数字 0-9 英文汉字 emoji 都不走这里，因为码点 <=255 是 Latin-1，其它是正常字符）
      ' 注意：修复双重UTF-8期间，遇到 U+4E00..U+9FFF (汉字) 说明前面没有双重编码，直接把暂存的 bytes 解码 UTF-8 + 保留汉字
      If k > 0 Then out = out & BytesToTextUTF8Safe(SliceByteArray(bytes, 0, k)) : k = 0
      out = out & ch
    End If
  Next
  If k > 0 Then out = out & BytesToTextUTF8Safe(SliceByteArray(bytes, 0, k))
  FixDoubleUTF8 = out
End Function

Function BytesToTextUTF8Safe(b)
  On Error Resume Next
  BytesToTextUTF8Safe = BytesToTextUTF8(b)
  If Err.Number <> 0 Then
    Err.Clear
    ' 解码失败，按 Latin-1 原封不动输出（避免丢掉内容）
    Dim i, s
    s = ""
    For i = 0 To UBound(b)
      s = s & Chr(b(i))
    Next
    BytesToTextUTF8Safe = s
  End If
  On Error GoTo 0
End Function

Function SliceByteArray(ByRef b, ByVal sIdx, ByVal cnt)
  Dim i, out()
  ReDim out(cnt - 1)
  For i = 0 To cnt - 1
    out(i) = b(sIdx + i)
  Next
  SliceByteArray = out
End Function

' VBS 没有原生 JSON.parse/stringify，借用 HTMLfile + eval 安全范围。
' 注意：仅当输入来自我们已修复好的 text（可信）才用这个方法。
Function EvalJson(ByVal text, outObj)
  On Error Resume Next
  Dim html, win, js
  Set html = CreateObject("HTMLfile")
  html.Write "<meta http-equiv=""x-ua-compatible"" content=""IE=edge""><script>var _v; function _parse(t){ _v = eval('(' + t + ')'); } function _s(o){return JSON.stringify(o, null, 2);}</script>"
  html.Close
  Set win = html.parentWindow
  win._parse CStr(text)
  If Err.Number <> 0 Then EvalJson = False : Set outObj = Nothing : Exit Function
  Set outObj = CreateObject("Scripting.Dictionary")
  outObj.Add "__value", win._v
  EvalJson = True
End Function

Function JSONStringify(ByVal parsed, ByVal indent)
  On Error Resume Next
  Dim html, win
  Set html = CreateObject("HTMLfile")
  html.Write "<meta http-equiv=""x-ua-compatible"" content=""IE=edge""><script>function _s(o){return JSON.stringify(o, null, 2);}</script>"
  html.Close
  Set win = html.parentWindow
  JSONStringify = win._s(parsed.Items()(0))
  If Err.Number <> 0 Then
    Err.Clear
    JSONStringify = ""
  End If
End Function
