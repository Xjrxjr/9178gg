@echo off
cd /d "%~dp0"

echo.
echo ============================================
echo   Deploy Website to Gitee Pages
echo ============================================
echo.

REM Check Git installation
where git >nul 2>nul
if errorlevel 1 (
    echo.
    echo [ERROR] Git not found!
    echo Please run install_git.bat first, or install Git manually.
    echo.
    pause
    exit /b 1
)

echo [1/4] Initializing Git repo (if not exists)...
if not exist ".git" (
    git init
    git config user.name "Xjrxjr"
    git config user.email "deploy@gitee.com"
    git config credential.helper manager
)

echo [2/4] Staging all files...
git add -A

echo [3/4] Committing changes...
REM Use simple date/time vars (no wmic dependency, compatible with all Windows versions)
set "d=%date:/=-%_%time::=-%"
set "d=%d:,=0%"
set "d=%d:.=0%"
set "commit_msg=update_website_%d%"
git commit -m "%commit_msg%" 2>nul
if errorlevel 1 (
    echo No new changes to commit.
)

echo [4/4] Pushing to Gitee...
git remote remove origin 2>nul
git remote add origin https://gitee.com/Xjrxjr/people.git

echo.
echo If login dialog appears, enter your Gitee username and password.
echo.

git push -u origin master 2>&1

echo.
echo ============================================
echo   Deploy Done!
echo ============================================
echo.
echo Next steps:
echo   1. Open: https://gitee.com/Xjrxjr/people
echo   2. Click Menu: [Services] -^> [Gitee Pages]
echo   3. Choose branch: master, then click [Start] or [Update]
echo   4. Visit your website: https://Xjrxjr.gitee.io/people/
echo.
pause
