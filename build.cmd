@echo off
setlocal
cd /d "%~dp0"

set "CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo [ERROR] csc.exe not found!
    exit /b 1
)

echo [1/3] Compiling Converter.exe...
"%CSC%" /target:winexe /optimize+ /platform:anycpu /win32icon:app.ico /out:Converter.exe src\Converter.cs
if errorlevel 1 exit /b 1

echo [2/3] Compiling menu-launcher.exe...
"%CSC%" /target:winexe /optimize+ /platform:anycpu /win32icon:app.ico /out:menu-launcher.exe src\MenuLauncher.cs
if errorlevel 1 exit /b 1

echo [3/3] Compiling Uninstall.exe...
"%CSC%" /target:winexe /optimize+ /platform:anycpu /win32icon:app.ico /out:Uninstall.exe src\Uninstall.cs
if errorlevel 1 exit /b 1

set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ISCC%" (
    echo [*] Building official Inno Setup installer...
    "%ISCC%" /Q installer.iss
)

echo [OK] All executables successfully compiled!
