@echo off
rem Dysnomia with the normal renderer (Forward+). Set GODOT below if Godot lives somewhere else.
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  pause
  exit /b 1
)
rem A fresh copy needs one import first (builds .godot\: the script class list and imported assets).
if not exist "%~dp0.godot\global_script_class_cache.cfg" (
  echo First run: importing the project, this takes a few minutes...
  "%GODOT%" --headless --path "%~dp0." --import
)
"%GODOT%" --path "%~dp0."
