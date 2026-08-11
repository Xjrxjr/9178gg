@echo off
cd /d "%~dp0"

echo.
echo ============================================
echo   People Website - Start Local Server
echo ============================================
echo.

REM Try py launcher first (official recommended)
where py >nul 2>nul
if %errorlevel%==0 (
    echo Starting server with py launcher...
    echo.
    py "%~dp0serve.py"
    goto :end
)

REM Then try python command
where python >nul 2>nul
if %errorlevel%==0 (
    echo Starting server with python...
    echo.
    python "%~dp0serve.py"
    goto :end
)

REM Neither found
echo.
echo ============================================
echo   Python NOT detected!
echo ============================================
echo.
echo Please install Python first:
echo.
echo   Option 1 (Recommended): Download from official site
echo   https://www.python.org/downloads/
echo   During installation, CHECK "Add Python to PATH"
echo.
echo   Option 2: Search "Python" in Microsoft Store and install
echo.
echo After installation, double-click this file again.
echo.
pause
exit /b 1

:end
if errorlevel 1 (
    echo.
    echo Server exited unexpectedly. Please check messages above.
    pause
)
