@echo off
rem Dysnomia with the normal renderer (Forward+). Set GODOT below if Godot lives somewhere else.
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  pause
  exit /b 1
)
rem Import first, every time: a pull can add scripts and assets, and the game only
rem sees new classes once they are imported. Quick when nothing changed; the first run takes minutes.
echo Importing new or changed files...
"%GODOT%" --headless --path "%~dp0." --import
"%GODOT%" --path "%~dp0."
