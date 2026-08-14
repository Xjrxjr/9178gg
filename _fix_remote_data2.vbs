' fix_remote_data2.vbs
Option Explicit

Dim fso, baseDir, inPath, outPath, inBytes, sIn, sFixed
Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
inPath  = fso.BuildPath(baseDir, "remote_data.json")
outPath = fso.BuildPath(baseDir, "data_fixed.json")

If Not fso.FileExists(inPath) Then
  WScript.Echo "[ERROR] missing remote_data.json"
  WScript.Quit 1
End If

inBytes = ReadAllBytes(inPath)
sIn     = BytesToUTF8(inBytes)
sFixed  = FixDouble(sIn)

WriteUTF8NoBom outPath, sFixed
WScript.Echo "Wrote " & outPath

Function ReadAllBytes(p)
  Dim st
  Set st = CreateObject("ADODB.Stream")
  st.Type = 1 : st.Open : st.LoadFromFile p
  ReadAllBytes = st.Read : st.Close
End Function

Sub WriteAllBytes(p, b)
  Dim st
  Set st = CreateObject("ADODB.Stream")
  st.Type = 1 : st.Open : st.Write b : st.SaveToFile p, 2 : st.Close
End Sub

Function BytesToUTF8(b)
  Dim st
  Set st = CreateObject("ADODB.Stream")
  st.Type = 1 : st.Open : st.Write b : st.Position = 0
  st.Type = 2 : st.Charset = "UTF-8"
  BytesToUTF8 = st.ReadText(-1) : st.Close
End Function

Sub WriteUTF8NoBom(p, txt)
  Dim st
  Set st = CreateObject("ADODB.Stream")
  st.Type = 2 : st.Charset = "UTF-8" : st.Open : st.WriteText txt
  st.Position = 0 : st.Type = 1
  st.Position = 3
  Dim noBom : noBom = st.Read(-1) : st.Close
  WriteAllBytes p, noBom
End Sub

Function FixDouble(ByVal s)
  If s = "" Then FixDouble = "" : Exit Function
  Dim n, i, cp, bytes(), k, out, chunk
  n = Len(s)
  ReDim bytes(n - 1)
  k = 0 : out = ""
  For i = 1 To n
    cp = AscW(Mid(s, i, 1))
    If cp < 0 Then cp = cp + 65536
    If cp <= 255 Then
      bytes(k) = CByte(cp And &HFF)
      k = k + 1
    Else
      If k > 0 Then out = out & SafeUTF8(Slice(bytes, 0, k)) : k = 0
      out = out & Mid(s, i, 1)
    End If
  Next
  If k > 0 Then out = out & SafeUTF8(Slice(bytes, 0, k))
  FixDouble = out
End Function

Function SafeUTF8(b)
  On Error Resume Next
  SafeUTF8 = BytesToUTF8(b)
  If Err.Number <> 0 Then
    Err.Clear
    Dim i, t : t = ""
    For i = 0 To UBound(b) : t = t & Chr(b(i)) : Next
    SafeUTF8 = t
  End If
  On Error GoTo 0
End Function

Function Slice(ByRef b, s, cnt)
  Dim i, o() : ReDim o(cnt - 1)
  For i = 0 To cnt - 1 : o(i) = b(s + i) : Next
  Slice = o
End Function
