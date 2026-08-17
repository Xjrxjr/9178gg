$ErrorActionPreference='SilentlyContinue'
$dirs = @()
$procs = @('FiveM.exe','FiveM_b*_GTAProcess.exe','GTA5.exe','PlayGTAV.exe','GTAVLauncher.exe','FiveM_Steam.exe')
Write-Host "语法检查通过。将添加进程排除项 $($procs.Count) 个，文件夹排除项 $($dirs.Count) 个（实际运行时动态填入）"
