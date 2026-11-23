@echo off
rem Dysnomia with the normal renderer (Forward+). Set GODOT below if Godot lives somewhere else.
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  pause
  exit /b 1
)
"%GODOT%" --path "%~dp0."
