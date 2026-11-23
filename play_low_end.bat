@echo off
rem Dysnomia on a PC without a real GPU: the lightweight OpenGL renderer and Potato quality.
rem Set GODOT below if Godot lives somewhere else.
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  echo Edit play_low_end.bat and set GODOT to your Godot .exe
  pause
  exit /b 1
)
rem A fresh copy needs one import first (builds .godot\: the script class list and imported assets).
if not exist "%~dp0.godot\global_script_class_cache.cfg" (
  echo First run: importing the project, this takes a few minutes...
  "%GODOT%" --headless --path "%~dp0." --import
)
"%GODOT%" --path "%~dp0." --rendering-method gl_compatibility -- --quality=0
