; Dysnomia — Windows installer (NSIS 3, Modern UI 2). Built in CI on Linux by release.yml:
;   makensis -DVERSION=1.2.3 -DSRC_DIR=<abs build/windows> -DOUT_FILE=<abs dist/…-setup.exe> [-DICON=<abs .ico>] dysnomia.nsi
;
; Per-user: no admin prompt, installs to %LOCALAPPDATA%\Programs\Dysnomia, registers under HKCU.
; Upgrading runs the same installer over the old one: same folder (read back from the uninstall
; key), the two files replaced. The player's data (user://, i.e. %APPDATA%\Godot\app_userdata\Dysnomia:
; settings, caches, wallet-relay state) is never touched by install or uninstall.
;
; Unsigned: Windows SmartScreen shows "Windows protected your PC" on first run (More info → Run anyway)
; until the build is code-signed (docs/RELEASE_CHECKLIST.md, docs/SECURITY_AUDIT.md).

Unicode true
SetCompressor /SOLID lzma
ManifestDPIAware true

!ifndef VERSION
  !error "Pass the version: makensis -DVERSION=x.y.z"
!endif
!searchparse /noerrors "${VERSION}" "" V_MAJ "." V_MIN "." V_PAT
!ifndef V_PAT
  !error "VERSION must be x.y.z (got ${VERSION})"
!endif
!ifndef SRC_DIR
  !define SRC_DIR "..\..\build\windows"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "..\..\dist\Dysnomia-${VERSION}-windows-setup.exe"
!endif

!define APP "Dysnomia"
!define EXE "Dysnomia.exe"
!define PCK "Dysnomia.pck"
!define PUBLISHER "Dysnomia community project"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dysnomia"

!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

Name "${APP}"
OutFile "${OUT_FILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${APP}"
; An earlier install (possibly in a folder the player chose) is upgraded in place.
InstallDirRegKey HKCU "${UNINST_KEY}" "InstallLocation"
BrandingText "${APP} ${VERSION}"

VIProductVersion "${V_MAJ}.${V_MIN}.${V_PAT}.0"
VIFileVersion "${V_MAJ}.${V_MIN}.${V_PAT}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP} ${VERSION} setup"
VIAddVersionKey "LegalCopyright" "${PUBLISHER}"

!ifdef ICON
  !define MUI_ICON "${ICON}"
  !define MUI_UNICON "${ICON}"
!endif
!define MUI_ABORTWARNING

Var DesktopShortcut   ; 1 = create the Desktop shortcut
Var DesktopBox

; Who made it (the same words as About.COMMUNITY_NOTICE in the game)
!define MUI_WELCOMEPAGE_TEXT "This will install ${APP} ${VERSION} for your Windows user (no administrator needed).$\r$\n$\r$\nA community project: not made, endorsed or run by the creator of Dysnomia. Fan-built, free, use at your own risk.$\r$\n$\r$\nThe game never asks for your seed phrase or private keys: your browser wallet signs every transaction.$\r$\n$\r$\nClick Next to continue."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
Page custom OptionsPage OptionsLeave
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${APP}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"


Function .onInit
  SetShellVarContext current
  ; Fresh install: a Desktop shortcut by default. Upgrade: keep whatever the player had.
  StrCpy $DesktopShortcut 1
  ReadRegStr $0 HKCU "${UNINST_KEY}" "InstallLocation"
  ${If} $0 != ""
  ${AndIfNot} ${FileExists} "$DESKTOP\${APP}.lnk"
    StrCpy $DesktopShortcut 0
  ${EndIf}
FunctionEnd


Function OptionsPage
  !insertmacro MUI_HEADER_TEXT "Shortcuts" "Choose where ${APP} can be started from."
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateLabel} 0 0 100% 24u "A Start Menu shortcut is always created."
  Pop $0
  ${NSD_CreateCheckbox} 0 30u 100% 12u "Create a &Desktop shortcut"
  Pop $DesktopBox
  ${If} $DesktopShortcut == 1
    ${NSD_Check} $DesktopBox
  ${EndIf}
  nsDialogs::Show
FunctionEnd


Function OptionsLeave
  ${NSD_GetState} $DesktopBox $DesktopShortcut
  ${If} $DesktopShortcut == ${BST_CHECKED}
    StrCpy $DesktopShortcut 1
  ${Else}
    StrCpy $DesktopShortcut 0
  ${EndIf}
FunctionEnd


Section "Dysnomia" SecMain
  SectionIn RO
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  SetOverwrite on
  ; Only the game's two files. A running copy keeps them locked: NSIS then asks Retry/Cancel.
  File "${SRC_DIR}\${EXE}"
  File "${SRC_DIR}\${PCK}"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  CreateDirectory "$SMPROGRAMS"
  CreateShortcut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
  ${If} $DesktopShortcut == 1
    CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
  ${Else}
    Delete "$DESKTOP\${APP}.lnk"
  ${EndIf}

  ; Add/Remove Programs (per user)
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$\"$INSTDIR\${EXE}$\",0"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" "$\"$INSTDIR\uninstall.exe$\" /S"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd


Section "Uninstall"
  SetShellVarContext current
  ; Exactly what the installer wrote. No recursive delete: $INSTDIR may be a folder the player
  ; chose, and the player's data lives in %APPDATA% (user://), which is left alone.
  Delete "$INSTDIR\${EXE}"
  Delete "$INSTDIR\${PCK}"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  DeleteRegKey HKCU "${UNINST_KEY}"
SectionEnd
