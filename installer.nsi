!include "MUI2.nsh"

; =========================
; Definitions
; =========================
!define APP_NAME "Bulk_Barcode"
!define VERSION "Release_1.1.4"
!define INSTALLER_NAME "${APP_NAME}_Setup.exe"
!define OUT_DIR "dist"

; Installer appearance
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\win-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\win-uninstall.ico"

; === Enable and define Header image ===
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Header\orange.bmp"
!define MUI_HEADERIMAGE_UNBITMAP "${NSISDIR}\Contrib\Graphics\Header\orange-uninstall.bmp"

; Welcome/Finish page images
!define MUI_WELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\win.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\orange-uninstall.bmp"

; Installer text
!define MUI_WELCOMEPAGE_TITLE "Welcome to the ${APP_NAME} Installer"
!define MUI_WELCOMEPAGE_TEXT "Install the Bulk Barcode for Windows. It can make barcodes / QR codes in bulk. Click on 'Next >' to continue."
!define MUI_FINISHPAGE_TITLE "Setup Complete"
!define MUI_FINISHPAGE_TEXT "Bulk Barcode has been installed on your computer. Click 'Finish' to exit the setup."

; Uninstaller text
!define MUI_UNWELCOMEPAGE_TITLE "Uninstall ${APP_NAME}"
!define MUI_UNWELCOMEPAGE_TEXT "This will uninstall ${APP_NAME} from your computer."
!define MUI_UNFINISHPAGE_TITLE "${APP_NAME} Uninstall Complete"
!define MUI_UNFINISHPAGE_TEXT "${APP_NAME} has been removed from your computer."

; Caption text
Caption "Install Bulk Barcode"
UninstallCaption "Uninstall Bulk Barcode"

; =========================
; Output & Install Settings
; =========================
OutFile "${OUT_DIR}\${INSTALLER_NAME}"
InstallDir "$PROGRAMFILES\${APP_NAME}"
RequestExecutionLevel admin
SetCompress auto
SetCompressor lzma

; =========================
; Pages
; =========================
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE LICENSE.txt
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

; =========================
; Installation Section
; =========================
Section "Install"
  SetOutPath "$INSTDIR"
  File /r "build\windows\x64\runner\Release\*"
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\bulk_barcode.exe"
SectionEnd

; =========================
; Post-Install: Register Uninstaller
; =========================
Section -Post
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" "$INSTDIR\Uninstall.exe"
SectionEnd

; =========================
; Uninstallation Section
; =========================
Section "Uninstall" UNINSTALL
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$INSTDIR\bulk_barcode.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
SectionEnd