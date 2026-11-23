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
rem Import first, every time: a pull can add scripts and assets, and the game only
rem sees new classes once they are imported. Quick when nothing changed; the first run takes minutes.
echo Importing new or changed files...
"%GODOT%" --headless --path "%~dp0." --import
"%GODOT%" --path "%~dp0." --rendering-method gl_compatibility -- --quality=0
