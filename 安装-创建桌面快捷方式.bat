@echo off
setlocal
chcp 65001 >nul
echo ============================================
echo   9178GG - Install Desktop Shortcut
echo   Creates a desktop icon for Admin Panel
echo ============================================

set "SCRIPT_DIR=%~dp0"
set "ADMIN_HTML=%SCRIPT_DIR%admin.html"
set "LAUNCH_VBS=%SCRIPT_DIR%9178后台管理.vbs"
set "URL_FILE=%SCRIPT_DIR%9178后台管理.url"

REM --- Find current user desktop path (no admin required) ---
set "DESKTOP=%USERPROFILE%\Desktop"
if not exist "%DESKTOP%" (
  for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" 2^>nul`) do (
    set "DESKTOP=%%D"
  )
)
if not exist "%DESKTOP%" (
  echo [ERROR] Cannot locate desktop path: %DESKTOP%
  echo Please manually copy files to your desktop.
  pause
  exit /b 1
)
echo Target desktop : %DESKTOP%
echo Script dir     : %SCRIPT_DIR%

REM --- Source file check ---
set "TARGET_EXE="
if exist "%LAUNCH_VBS%" (
  set "TARGET_EXE=%LAUNCH_VBS%"
  echo Silent launcher: OK (%LAUNCH_VBS%)
) else (
  echo [WARN] VBS launcher missing, fallback to admin.html directly
  set "TARGET_EXE=%ADMIN_HTML%"
)

REM ============================================================
REM Step 1: Create native .lnk shortcut via WScript.Shell (COM)
REM ============================================================
set "LNK_OUT=%DESKTOP%\9178后台管理.lnk"
set "TMP_VBS=%TEMP%\make_9178gg_shortcut_%RANDOM%.vbs"

echo Creating native .lnk shortcut...
echo Set sh = CreateObject("WScript.Shell")                             > "%TMP_VBS%"
echo Set lnk = sh.CreateShortcut("%LNK_OUT%")                          >> "%TMP_VBS%"
echo lnk.TargetPath       = "%TARGET_EXE%"                             >> "%TMP_VBS%"
echo lnk.WorkingDirectory = "%SCRIPT_DIR%"                             >> "%TMP_VBS%"
echo lnk.Description      = "9178GG - Admin Panel (后台管理)"         >> "%TMP_VBS%"
echo lnk.IconLocation     = "%SystemRoot%\System32\imageres.dll,175"   >> "%TMP_VBS%"
echo lnk.WindowStyle      = 1                                          >> "%TMP_VBS%"
echo lnk.Save                                                           >> "%TMP_VBS%"

cscript //nologo "%TMP_VBS%"
set LNK_ERR=%ERRORLEVEL%
if exist "%TMP_VBS%" del /Q "%TMP_VBS%"

if %LNK_ERR% EQU 0 if exist "%LNK_OUT%" (
  echo [OK] .lnk shortcut created: %LNK_OUT%
) else (
  echo [FALLBACK] .lnk creation failed, copying .url and .vbs files directly to desktop.
  if exist "%URL_FILE%" (
    copy /Y "%URL_FILE%"  "%DESKTOP%\9178后台管理.url" >nul && echo [OK] Copied .url shortcut
  )
  if exist "%LAUNCH_VBS%" (
    copy /Y "%LAUNCH_VBS%" "%DESKTOP%\9178后台管理-启动器.vbs" >nul && echo [OK] Copied silent launcher (vbs)
  )
)

REM ============================================================
REM Step 2: Also create Start Menu shortcut for current user
REM ============================================================
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs\9178GG"
if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs" (
  if not exist "%START_MENU%" mkdir "%START_MENU%" 2>nul
  if exist "%START_MENU%" (
    if exist "%LNK_OUT%" (
      copy /Y "%LNK_OUT%" "%START_MENU%\9178后台管理.lnk" >nul 2>nul
      if %ERRORLEVEL% EQU 0 echo [OK] Start Menu entry added
    ) else (
      if exist "%URL_FILE%" copy /Y "%URL_FILE%" "%START_MENU%\9178后台管理.url" >nul 2>nul
    )
  )
)

REM ============================================================
REM Step 3: Copy launcher into J:\9178GG root if missing (done by file existence already)
REM ============================================================

echo.
echo ============================================
echo  Install complete.
echo  Look for "9178后台管理" on your desktop
echo  or in Start Menu -^> Programs -^> 9178GG.
echo ============================================
pause
endlocal
