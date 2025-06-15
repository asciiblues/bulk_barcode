Outfile "installer\Setup.exe"
InstallDir "$PROGRAMFILES\asciiblues\bulkbarcode"

Section
  SetOutPath "$INSTDIR"
  File /r "build\windows\x64\runner\Release\*"
  CreateShortCut "$DESKTOP\buckbarcode.lnk" "$INSTDIR\bulkbarcode.exe"
SectionEnd