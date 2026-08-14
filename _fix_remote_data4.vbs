' fix_remote_data4.vbs — Byte-level Double-UTF-8 undoer with safe Variant-to-bytes conversion.
Option Explicit

Dim fso, baseDir, inPath, outPath, inRawBytes, inArr, sz
Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
inPath  = fso.BuildPath(baseDir, "remote_data.json")
outPath = fso.BuildPath(baseDir, "data_fixed.json")

If Not fso.FileExists(inPath) Then WScript.Echo "Missing remote_data.json" : WScript.Quit 1

inRawBytes = ReadAllBytesArr(inPath)   ' plain vb array of Byte
sz = UBound(inRawBytes) + 1

Dim result, nOut, i, b1, b2, outByte
ReDim result(sz - 1)   ' max possible
nOut = 0

i = 0
Do While i < sz
  b1 = inRawBytes(i) And &HFF
  If (b1 = &HC2 Or b1 = &HC3) And (i + 1 < sz) Then
    b2 = inRawBytes(i + 1) And &HFF
    If (b2 And &HC0) = &H80 Then
      ' Decode double-encoded pair back to single original byte
      If b1 = &HC2 Then
        outByte = b2
      Else
        outByte = &HC0 + (b2 And &H3F)
      End If
      result(nOut) = CByte(outByte)
      nOut = nOut + 1
      i = i + 2
    Else
      result(nOut) = CByte(b1) : nOut = nOut + 1 : i = i + 1
    End If
  Else
    result(nOut) = CByte(b1) : nOut = nOut + 1 : i = i + 1
  End If
Loop

' Copy only the first nOut bytes to final array and write
Dim final
If nOut > 0 Then
  ReDim final(nOut - 1)
  Dim j : j = 0
  For j = 0 To nOut - 1 : final(j) = result(j) : Next
  WriteByteArray outPath, final
End If

WScript.Echo "wrote " & outPath & " size=" & nOut & " (orig size=" & sz & ")"

' ---- Helper: read file to VB array of Byte ----
Function ReadAllBytesArr(p)
  Dim st, raw, sz2, k
  Set st = CreateObject("ADODB.Stream")
  st.Type = 1 : st.Open : st.LoadFromFile p
  raw = st.Read   ' Variant containing safe array of bytes
  st.Close : Set st = Nothing
  sz2 = UBound(raw) + 1
  Dim out() : ReDim out(sz2 - 1)
  For k = 0 To sz2 - 1 : out(k) = CByte(AscB(MidB(raw, k + 1, 1))) : Next
  ReadAllBytesArr = out
End Function

' ---- Helper: write plain VB Byte-array to file via ADODB.Stream ----
Sub WriteByteArray(p, arr)
  Dim st, n, i
  Set st = CreateObject("ADODB.Stream")
  st.Type = 1 : st.Open
  n = UBound(arr) + 1
  For i = 0 To n - 1
    st.Write ChrB(arr(i))
  Next
  st.SaveToFile p, 2
  st.Close
End Sub
