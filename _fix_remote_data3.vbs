' fix_remote_data3.vbs — bytes level 修复 double-UTF-8
Option Explicit

Dim fso, baseDir, inPath, outPath
Dim bIn, sz, i, j, result(), nOut, b1, b2, b3, cp, cp1, outBytes

Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
inPath  = fso.BuildPath(baseDir, "remote_data.json")
outPath = fso.BuildPath(baseDir, "data_fixed.json")

If Not fso.FileExists(inPath) Then WScript.Echo "Missing remote_data.json" : WScript.Quit 1

bIn = ReadAllBytes(inPath)
sz  = UBound(bIn) + 1

' 先整体按 Latin-1 (ISO-8859-1) 解释: 每个字节 -> 相同码点字符。
' 然后按 UTF-8 规则去识别:
'  1) ASCII: 00-7F 直接保留
'  2) Double UTF-8: 正常 UTF-8 的 3 字节中文字符是 E8..AD..A6 这样 3 个字节(表示「警」)
'     被错误当作 Latin-1 三个字符后再次 UTF-8 编码, 于是变成:
'       C3 A8 C2 AD C2 A6 (6 字节组)
'       [C3 A8] -> U+00E8 (è) ; [C2 AD] -> U+00AD ; [C2 A6] -> U+00A6
'     所以 6 字节组的模式:
'       C3 A8 / C3 A5 / C3 AF / C2 AD / C2 A6 / C3 B7 / ... 对应第一个字节 = C2 或 C3, 后面跟 A0..BF
' 我们用 bytes 扫描:
'   If 当前字节是 C3 且下一个字节在 A0..BF -> 这是 double-UTF8 的第一个码点字节 (原始字节 = 0xC0 + 低字节 & 0x3F + 0x80? 不对)
'   实际上 double 编码的映射:
'     原始 UTF-8 字节 B (在 0x80..0xFF 范围内): 会被编码为 C2 xx (当 B<0xC0) 或 C3 xx' (当 B>=0xC0, 其中 xx'= B - 0x40)
'     因为 B 作为 Unicode 码点 U+00xx, 按 UTF-8 编码成 2 字节:
'       if xx<0x80: 单字节 (ASCII)
'       if 0x80<=xx<0xC0: 11000010 10xxxxxx 即 C2 (80+xx低6位) -> C2 xx
'       if 0xC0<=xx<=0xFF: 11000011 10(xx-0x80)xx? 等一下: U+00C0..U+00FF = 码点 0xC0..0xFF
'           按 UTF-8 编码: 码点 0xC0 -> 110 00011 : 10 000000  = C3 80? 不对, 算一下:
'           码点 0xC0: 0xC0 = 11000000 (8bit) = 7+1 bit, 需要 2 字节 UTF-8 形式: 110xxxxx 10yyyyyy, 其中 xxxxxyyyyyy = 码点.
'             0xC0 = 11000000, 切成 xxxxx = 00011, yyyyyy = 000000 -> 11000011 10000000 = C3 80. 对。
'           码点 0xE8 (è): 0xE8 = 11101000 -> xxxxx = 00111, yyyyyy = 101000 -> 11000011 10101000 = C3 A8. 对!
'           码点 0xAD (软连字符): 0xAD = 10101101 -> xxxxx = 00010, yyyyyy = 101101 -> 11000010 10101101 = C2 AD. 对!
'           码点 0xA6 (¦): 0xA6 = 10100110 -> xxxxx = 00010, yyyyyy = 100110 -> 11000010 10100110 = C2 A6. 对!
'
'   所以 double 编码 2-byte 序列 (C2 C3 开头 + 第二字节 80..BF) 对应原始单个字节 B:
'     case (Hi, Lo):
'       Hi = C2: B = 0x80 + (Lo & 0x3F)   (即 B = Lo, 因为 Lo 已经是 0x80..0xBF)
'       Hi = C3: B = 0xC0 + (Lo & 0x3F)   (即 B = Lo + 0x40)
'
'   ASCII 字节 (0x00..0x7F) 在双重编码里不变, 直接原样.

' 预分配结果数组 (最坏不超过输入大小)
ReDim result(sz - 1)
nOut = 0

i = 0
Do While i < sz
  b1 = bIn(i)
  If (b1 = &HC2 Or b1 = &HC3) And i + 1 < sz Then
    b2 = bIn(i + 1)
    If (b2 And &HC0) = &H80 Then
      ' 这是 double 编码的 2-byte 组, 还原为 1 字节
      If b1 = &HC2 Then
        outBytes = b2
      Else
        outBytes = &HC0 + (b2 And &H3F)
      End If
      result(nOut) = CByte(outBytes)
      nOut = nOut + 1
      i = i + 2
    Else
      result(nOut) = CByte(b1) : nOut = nOut + 1 : i = i + 1
    End If
  Else
    result(nOut) = CByte(b1) : nOut = nOut + 1 : i = i + 1
  End If
Loop

' 去掉多余长度 (nOut <= sz 一般 nOut < sz)
Dim final()
ReDim final(nOut - 1)
For j = 0 To nOut - 1 : final(j) = result(j) : Next

WriteAllBytes outPath, final
WScript.Echo "OK, wrote " & outPath & " (" & nOut & " bytes orig=" & sz & ")"

' Helpers
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
