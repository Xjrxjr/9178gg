@echo off
winget install Git.Git --source winget --accept-source-agreements --accept-package-agreements --silent
echo EXIT_CODE=%ERRORLEVEL%
