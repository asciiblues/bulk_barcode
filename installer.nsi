!define APP_NAME "Bulk_Barcode"
!define VERSION "Release 1.1.0"
!define INSTALLER_NAME "${APP_NAME}_Setup.exe"
!define OUT_DIR "dist"

OutFile "${OUT_DIR}\${INSTALLER_NAME}"
InstallDir "$PROGRAMFILES\${APP_NAME}"
RequestExecutionLevel admin
SetCompress auto
SetCompressor lzma

Page directory
Page instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "build\windows\x64\runner\Release\*"
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\bulk_barcode.exe"
SectionEnd