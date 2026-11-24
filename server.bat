@echo off
rem Dysnomia game server (docs\SERVER.md). Runs headless on this PC, listens on
rem 127.0.0.1 only; a tunnel (Tailscale Funnel or Cloudflare Tunnel) makes it
rem reachable without showing this PC's IP. Restarts itself if it ever stops.
rem Options go after the --, for example:  server.bat --port=8787 --name=MyServer
rem Logs: %APPDATA%\Godot\app_userdata\Dysnomia\server\server.log
set "DIR=%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64.exe"
set "GODOT=%DIR%\Godot_v4.6.1-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=%DIR%\Godot_v4.6.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found in %DIR%
  echo Edit the DIR line at the top of server.bat to point at your Godot folder.
  pause
  exit /b 1
)
echo Importing new or changed files...
"%GODOT%" --headless --path "%~dp0." --import
:loop
echo Starting the Dysnomia game server. Close this window or press Ctrl+C twice to stop it.
"%GODOT%" --headless --path "%~dp0." res://scenes/net/game_server.tscn -- %*
echo The server stopped (exit code %errorlevel%). Restarting in 5 seconds... (Ctrl+C to quit)
timeout /t 5 /nobreak >nul
goto loop
