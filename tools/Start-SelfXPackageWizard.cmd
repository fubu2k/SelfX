@echo off
rem SelfX package wizard (window): starts tools\Wizard\SelfXWizardGui.ps1 in Windows PowerShell 5.1 with a single-threaded apartment
rem (WPF). Context: build machine, own user account (no administrator rights needed). The console version tools\New-SelfXPackage.ps1
rem stays for automation (answer file).
rem Version 1.0.0 (2026-11-27): Initial version.
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Wizard\SelfXWizardGui.ps1"
exit /b %ERRORLEVEL%
