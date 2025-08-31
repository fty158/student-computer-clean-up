@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================
:: Student Lab Cleanup Script
:: Usage:  CleanLab.cmd [/DRYRUN]
:: ============================

:: --- Require elevation
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Please run this script as Administrator.
  exit /b 1
)

:: --- Dry run flag
set "DRYRUN=0"
if /i "%~1"=="/DRYRUN" set "DRYRUN=1"

:: --- Timestamp + log file (portable across locales)
for /f "tokens=1-5 delims=/:. " %%a in ("%date% %time%") do set "TS=%%a-%%b-%%c_%%d%%e"
set "LOG=%SystemRoot%\Temp\LabCleanup_%TS%.log"

:: ----------------- MAIN -----------------
call :Log ------------------------------------------------------------
call :Log Lab Cleanup started %DATE% %TIME%  (DRYRUN=%DRYRUN%)
call :Log Log: "%LOG%"
call :Log ------------------------------------------------------------

:: Public areas (keep .lnk on Public Desktop)
if exist "C:\Users\Public\Desktop" call :PruneDesktop "C:\Users\Public\Desktop"
if exist "C:\Users\Public\Documents" call :ClearFolder "C:\Users\Public\Documents"

:: Iterate user profiles (skip built-ins)
for /d %%P in ("C:\Users\*") do (
  set "THIS=%%~nxP"
  set "SKIP=0"
  for %%E in (Administrator "Default" "Default User" "All Users" Public WDAGUtilityAccount) do (
    if /i "!THIS!"=="%%~E" set "SKIP=1"
  )
  if "!THIS:~0,1!"=="." set "SKIP=1"
  if "!SKIP!"=="1" (
    call :Log [SKIP] %%~nxP
  ) else (
    call :CleanUser "%%~fP"
  )
)

:: Windows Temp
if exist "C:\Windows\Temp" call :DelFiles "C:\Windows\Temp\*.*"

:: Empty all Recycle Bins
if exist "C:\$Recycle.Bin" (
  if "%DRYRUN%"=="1" (
    call :Log [DRYRUN] Empty Recycle Bin
  ) else (
    rmdir /s /q "C:\$Recycle.Bin" 2>nul
    call :Log [OK] Emptied Recycle Bin
  )
)

call :Log ------------------------------------------------------------
call :Log Lab Cleanup finished %DATE% %TIME%
call :Log ------------------------------------------------------------
echo.
echo Done. Log: %LOG%
echo.
exit /b 0

:: ----------------- HELPERS -----------------

:Log
>>"%LOG%" echo %*
echo %*
exit /b

:DelDir
:: %1=fullPath  (guard against dangerous roots)
set "TARGET=%~1"
if not exist "%TARGET%" exit /b
if /i "%TARGET%"=="C:\" exit /b
if /i "%TARGET%"=="C:\Windows" exit /b
if /i "%TARGET%"=="C:\Users" exit /b

if "%DRYRUN%"=="1" (
  call :Log [DRYRUN] rmdir /s /q "%TARGET%"
) else (
  attrib -r -s -h "%TARGET%" /s /d >nul 2>&1
  rmdir /s /q "%TARGET%" 2>nul
  if exist "%TARGET%" (
    call :Log [WARN] Could not remove "%TARGET%"
  ) else (
    call :Log [OK] Removed "%TARGET%"
  )
)
exit /b

:DelFiles
:: %1=pattern (wildcards OK)
set "PATTERN=%~1"
if "%DRYRUN%"=="1" (
  call :Log [DRYRUN] del /f /s /q "%PATTERN%"
) else (
  del /f /s /q "%PATTERN%" 2>nul
  call :Log [OK] Cleared files "%PATTERN%"
)
exit /b

:CleanUser
:: %1=user profile root (e.g., C:\Users\alice)
set "UP=%~1"
for %%U in ("%UP%") do set "UN=%%~nU"
call :Log === Cleaning user "%UN%" at "%UP%" ===

:: Desktop – keep .lnk shortcuts at top level; remove all other files and subfolders
if exist "%UP%\Desktop" call :PruneDesktop "%UP%\Desktop"

:: Remove common content folders entirely
for %%D in ("Documents" "Downloads" "Pictures" "Videos" "Music" "3D Objects") do (
  call :ClearFolder "%UP%\%%~D"
)

:: Finally, prune unexpected root files/folders in the user profile
call :PruneUserRoot "%UP%"

:: OneDrive (keep root, clear contents)
if exist "%UP%\OneDrive" call :DelFiles "%UP%\OneDrive\*.*"

:: Per-user Temp
if exist "%UP%\AppData\Local\Temp" call :DelFiles "%UP%\AppData\Local\Temp\*.*"

:: Recent & Jump Lists
if exist "%UP%\AppData\Roaming\Microsoft\Windows\Recent" call :DelFiles "%UP%\AppData\Roaming\Microsoft\Windows\Recent\*.*"
if exist "%UP%\AppData\Roaming\Microsoft\Windows\Recent\AutomaticDestinations" call :DelFiles "%UP%\AppData\Roaming\Microsoft\Windows\Recent\AutomaticDestinations\*.*"
if exist "%UP%\AppData\Roaming\Microsoft\Windows\Recent\CustomDestinations" call :DelFiles "%UP%\AppData\Roaming\Microsoft\Windows\Recent\CustomDestinations\*.*"

:: Edge/Chrome caches
:: Nuke Chrome & Edge profiles entirely (fresh browser state)
for %%B in ("Microsoft\Edge" "Google\Chrome") do (
  if exist "%UP%\AppData\Local\%%~B\User Data" (
    call :ClearAllChromeProfiles "%UP%\AppData\Local\%%~B\User Data"
  )
)


:: Nuke all Firefox profiles (fresh browser state)
set "FF_APPDATA=%UP%\AppData\Roaming\Mozilla\Firefox\Profiles"
set "FF_LOCAL=%UP%\AppData\Local\Mozilla\Firefox\Profiles"
call :ClearAllFirefoxProfiles "%FF_APPDATA%" "%FF_LOCAL%"


:: VS Code caches
if exist "%UP%\AppData\Roaming\Code\Cache" call :DelDir "%UP%\AppData\Roaming\Code\Cache"
if exist "%UP%\AppData\Roaming\Code\CachedData" call :DelDir "%UP%\AppData\Roaming\Code\CachedData"

call :Log === Done user "%UN%" ===
exit /b

:PruneDesktop
:: %1=Desktop path — keep .lnk at top level, remove everything else
set "DESK=%~1"

:: Delete non-.lnk files at top level
for %%F in ("%DESK%\*") do (
  if exist "%%~fF" if /i not "%%~xF"==".lnk" (
    if "%DRYRUN%"=="1" (
      call :Log [DRYRUN] del /f /q "%%~fF"
    ) else (
      del /f /q "%%~fF" 2>nul
    )
  )
)

:: Remove all subfolders under Desktop
for /d %%D in ("%DESK%\*") do (
  if "%DRYRUN%"=="1" (
    call :Log [DRYRUN] rmdir /s /q "%%~fD"
  ) else (
    rmdir /s /q "%%~fD" 2>nul
  )
)

call :Log [OK] Cleaned Desktop at "%DESK%" (shortcuts kept)
exit /b

:ClearFolder
:: %1 = folder path (keep the folder, remove all contents)
set "FOLDER=%~1"

if not exist "%FOLDER%" (
  if "%DRYRUN%"=="1" (
    call :Log [DRYRUN] mkdir "%FOLDER%"
  ) else (
    mkdir "%FOLDER%" 2>nul
  )
  call :Log [OK] Ensured folder exists "%FOLDER%"
  exit /b
)

:: delete files in folder
if "%DRYRUN%"=="1" (
  call :Log [DRYRUN] del /f /q "%FOLDER%\*"
) else (
  del /f /q "%FOLDER%\*" 2>nul
)

:: delete subfolders
for /d %%D in ("%FOLDER%\*") do (
  if "%DRYRUN%"=="1" (
    call :Log [DRYRUN] rmdir /s /q "%%~fD"
  ) else (
    rmdir /s /q "%%~fD" 2>nul
  )
)

call :Log [OK] Cleared contents of "%FOLDER%" (folder kept)
exit /b

:ClearChromeProfile
:: %1 = Chrome profile root (e.g., ...\User Data\Default)
set "CPROFILE=%~1"

if not exist "%CPROFILE%" exit /b

:: Delete cache subfolders
call :DelDir "%CPROFILE%\Cache"
call :DelDir "%CPROFILE%\Code Cache"
call :DelDir "%CPROFILE%\GPUCache"
call :DelDir "%CPROFILE%\Media Cache"

:: Delete cookies, saved logins, autofill databases
for %%F in (
  "Cookies"
  "Login Data"
  "Login Data For Account"
  "Web Data"
  "AutofillStrikeDatabase"
  "History"
  "Network Action Predictor"
  "Shortcuts"
  "Top Sites"
  "Visited Links"
  "Preferences"
  "Secure Preferences"
  "Local Storage"
) do (
  if exist "%CPROFILE%\%%~F" (
    if "%DRYRUN%"=="1" (
      call :Log [DRYRUN] del /f /q "%CPROFILE%\%%~F"
    ) else (
      del /f /q "%CPROFILE%\%%~F" 2>nul
    )
  )
)

call :Log [OK] Cleared Chrome profile "%CPROFILE%" (cache + logins + prefs)
exit /b

:ClearFirefoxProfile
:: %1 = Roaming Firefox profile (e.g., ...\AppData\Roaming\Mozilla\Firefox\Profiles\xxxx.default-release)
set "FFP=%~1"
if not exist "%FFP%" exit /b

:: Delete key credential & session stores
for %%F in (
  "logins.json"
  "key4.db" "key3.db"
  "cert9.db" "cert8.db"
  "cookies.sqlite"
  "formhistory.sqlite"
  "places.sqlite" "favicons.sqlite"
  "permissions.sqlite"
  "webappsstore.sqlite"
  "content-prefs.sqlite"
  "handlers.json"
  "search.json.mozlz4"
  "sessionstore.jsonlz4"
) do (
  if exist "%FFP%\%%~F" (
    if "%DRYRUN%"=="1" (call :Log [DRYRUN] del /f /q "%FFP%\%%~F") else (del /f /q "%FFP%\%%~F" 2>nul)
  )
)

:: Session backups, local storage, service worker data
if exist "%FFP%\sessionstore-backups" call :DelDir "%FFP%\sessionstore-backups"
if exist "%FFP%\storage"              call :DelDir "%FFP%\storage"

:: Clean SQLite sidecar files
for %%G in ("%FFP%\*.sqlite-wal" "%FFP%\*.sqlite-shm") do (
  if exist "%%~fG" (
    if "%DRYRUN%"=="1" (call :Log [DRYRUN] del /f /q "%%~fG") else (del /f /q "%%~fG" 2>nul)
  )
)

call :Log [OK] Cleared Firefox profile "%FFP%" (logins, cookies, history, storage)
exit /b


:ClearFirefoxCache
:: %1 = Local Firefox profile (e.g., ...\AppData\Local\Mozilla\Firefox\Profiles\xxxx.default-release)
set "FFL=%~1"
if not exist "%FFL%" exit /b

:: Cache folders
for %%D in ("cache2" "startupCache") do (
  if exist "%FFL%\%%~D" call :DelDir "%FFL%\%%~D"
)

call :Log [OK] Cleared Firefox caches "%FFL%"
exit /b

:PruneUserRoot
:: %1 = user profile root, e.g., C:\Users\alice
set "UROOT=%~1"
if not exist "%UROOT%" exit /b

:: Standard root items to keep (quote those with spaces)
set "KEEP_LIST=AppData Desktop Documents Downloads Pictures Videos Music OneDrive "3D Objects" Favorites Links Contacts "Saved Games" Searches"

:: ---------- Remove unexpected DIRECTORIES ----------
for /d %%D in ("%UROOT%\*") do (
  set "ITEM=%%~nxD"
  set "KEEP=0"

  :: Keep standard folders
  for %%W in (%KEEP_LIST%) do (
    if /i "%%~W"=="!ITEM!" set "KEEP=1"
  )

  :: Skip reparse points (symlinks/junctions)
  for %%A in ("%%~fD") do set "ATTR=%%~aA"
  echo.!ATTR!| find /i "l" >nul && set "KEEP=1"

  if "!KEEP!"=="1" (
    call :Log [KEEP] "%%~fD"
  ) else (
    if "%DRYRUN%"=="1" (
      call :Log [DRYRUN] rmdir /s /q "%%~fD"
    ) else (
      attrib -r -s -h "%%~fD" /s /d >nul 2>&1
      rmdir /s /q "%%~fD" 2>nul
      if exist "%%~fD\NUL" (call :Log [WARN] Could not remove "%%~fD") else (call :Log [OK] Removed "%%~fD")
    )
  )
)

:: ---------- Remove unexpected FILES ----------
for /f "delims=" %%F in ('dir /a:-d /b "%UROOT%"') do (
  set "ITEM=%%~nxF"
  set "KEEP=0"

  :: Always keep core registry/user hive files
  if /i "!ITEM!"=="NTUSER.DAT"        set "KEEP=1"
  if /i "!ITEM:~0,9!"=="NTUSER.DA"    set "KEEP=1"   & rem NTUSER.DAT.LOG*, .POL, etc.
  if /i "!ITEM!"=="ntuser.ini"         set "KEEP=1"
  if /i "!ITEM:~0,11!"=="UsrClass.dat" set "KEEP=1"

  if "!KEEP!"=="1" (
    call :Log [KEEP] "%UROOT%\!ITEM!"
  ) else (
    if "%DRYRUN%"=="1" (
      call :Log [DRYRUN] del /f /q "%UROOT%\!ITEM!"
    ) else (
      attrib -r -s -h "%UROOT%\!ITEM!" >nul 2>&1
      del /f /q "%UROOT%\!ITEM!" 2>nul
      if exist "%UROOT%\!ITEM!" (call :Log [WARN] Could not delete "%UROOT%\!ITEM!") else (call :Log [OK] Deleted "%UROOT%\!ITEM!")
    )
  )
)

exit /b

:ClearAllChromeProfiles
:: %1 = Chrome base path (e.g., ...\AppData\Local\Google\Chrome\User Data)
set "CROOT=%~1"
if not exist "%CROOT%" exit /b

if "%DRYRUN%"=="1" (
  call :Log [DRYRUN] rmdir /s /q "%CROOT%"
) else (
  attrib -r -s -h "%CROOT%" /s /d >nul 2>&1
  rmdir /s /q "%CROOT%" 2>nul
  if exist "%CROOT%" (
    call :Log [WARN] Could not remove all Chrome profiles in "%CROOT%"
  ) else (
    call :Log [OK] Deleted all Chrome profiles in "%CROOT%"
  )
)

exit /b

:ClearAllFirefoxProfiles
:: %1 = Firefox profiles base (e.g., ...\AppData\Roaming\Mozilla\Firefox\Profiles)
:: %2 = Firefox local profiles base (e.g., ...\AppData\Local\Mozilla\Firefox\Profiles)

set "FFROAM=%~1"
set "FFLOCAL=%~2"

:: Remove roaming profiles (logins, prefs, history, add-ons)
if exist "%FFROAM%" (
  if "%DRYRUN%"=="1" (
    call :Log [DRYRUN] rmdir /s /q "%FFROAM%"
  ) else (
    attrib -r -s -h "%FFROAM%" /s /d >nul 2>&1
    rmdir /s /q "%FFROAM%" 2>nul
    if exist "%FFROAM%" (
      call :Log [WARN] Could not remove roaming profiles in "%FFROAM%"
    ) else (
      call :Log [OK] Deleted all Firefox roaming profiles in "%FFROAM%"
    )
  )
)

:: Remove local caches/profiles
if exist "%FFLOCAL%" (
  if "%DRYRUN%"=="1" (
    call :Log [DRYRUN] rmdir /s /q "%FFLOCAL%"
  ) else (
    attrib -r -s -h "%FFLOCAL%" /s /d >nul 2>&1
    rmdir /s /q "%FFLOCAL%" 2>nul
    if exist "%FFLOCAL%" (
      call :Log [WARN] Could not remove local profiles in "%FFLOCAL%"
    ) else (
      call :Log [OK] Deleted all Firefox local profiles in "%FFLOCAL%"
    )
  )
)

exit /b
