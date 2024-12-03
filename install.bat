@echo off
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"

echo ===============================
echo Installing Smart Connect System
echo ===============================

:: ตรวจสอบไฟล์ ZIP
if not exist "%~dp0SmartOPD.zip" (
    echo Error: SmartOPD.zip not found!
    echo Please make sure SmartOPD.zip exists in the same folder as this installer.
    echo.
    pause
    exit /b 1
)

:: กำหนดพาธสำหรับติดตั้งใน C drive
set "INSTALL_PATH=C:\SmartOPD"

:: ลบโฟลเดอร์เก่าถ้ามี
echo Cleaning up old installation...
if exist "%INSTALL_PATH%" (
    rd /s /q "%INSTALL_PATH%"
)

:: สร้างโฟลเดอร์ติดตั้งใหม่

echo Creating installation directory...
mkdir "%INSTALL_PATH%"

:: แตกไฟล์ ZIP
echo Extracting files...
powershell -Command "Expand-Archive -Path '%~dp0SmartOPD.zip' -DestinationPath '%INSTALL_PATH%' -Force"
if errorlevel 1 (
    echo Error: Failed to extract SmartOPD.zip
    echo Please run this installer as administrator.
    echo.
    pause
    exit /b 1
)

:: ตรวจสอบเวอร์ชัน Node.js
for /f "tokens=1,2,3 delims=." %%a in ('node -v 2^>nul') do (
    set "NODE_MAJOR=%%a"
    set "NODE_MINOR=%%b"
    set "NODE_PATCH=%%c"
)

:: ถ้าไม่มี Node.js หรือเวอร์ชันไม่ตรง (ต้องการ v20)
if "%NODE_MAJOR%" neq "v20" (
    echo Installing Node.js v20.9.0...
    powershell -Command "Invoke-WebRequest -Uri 'https://nodejs.org/dist/v20.9.0/node-v20.9.0-x64.msi' -OutFile '%TEMP%\node_installer.msi'"
    msiexec /i "%TEMP%\node_installer.msi" /qn
    del "%TEMP%\node_installer.msi"
    
    echo Waiting for Node.js installation to complete...
    timeout /t 10 /nobreak

    :: รีเฟรช PATH
    for /f "delims=" %%i in ('powershell -Command "[System.Environment]::GetEnvironmentVariable('Path', 'Machine')"') do set "PATH=%%i;%PATH%"
) else (
    echo Node.js v%NODE_MAJOR%.%NODE_MINOR%.%NODE_PATCH% is already installed
)

:: ติดตั้ง dependencies
cd /d "%INSTALL_PATH%"
if exist "package.json" (
    echo Installing project dependencies...
    call npm install
) else (
    echo Warning: package.json not found in extracted files
)

:: สร้าง start.bat ไว้ที่ Desktop
echo Creating start.bat on desktop...
(
echo @echo off
echo :: ซ่อนหน้าต่าง CMD และรอให้ระบบพร้อม
echo timeout /t 10 /nobreak ^> nul
echo if not DEFINED IS_MINIMIZED set IS_MINIMIZED=1 ^&^& start "" /min "%%~dpnx0" %%* ^&^& exit
echo.
echo cd /d "%INSTALL_PATH%\SmartOPD"
echo.
echo :: รันเซิร์ฟเวอร์และรอให้พร้อม
echo start /min cmd /c "node server.js"
echo.
echo :checkServer
echo timeout /t 2 /nobreak ^> nul
echo powershell -Command "(Test-NetConnection localhost -Port 3000).TcpTestSucceeded" ^| findstr "True" ^> nul
echo if errorlevel 1 goto checkServer
echo.
echo :: เปิดเบราว์เซอร์แบบ kiosk mode
echo start "" msedge --kiosk "http://localhost:3000" --edge-kiosk-type=fullscreen
echo if errorlevel 1 ^(
echo     start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" --kiosk "http://localhost:3000"
echo     if errorlevel 1 ^(
echo         start firefox -kiosk "http://localhost:3000"
echo         if errorlevel 1 ^(
echo             start http://localhost:3000
echo         ^)
echo     ^)
echo ^)
) > "%userprofile%\Desktop\SmartOPD_start.bat"

:: คัดลอกไฟล์ icon ถ้ามี
if exist "%~dp0icon.ico" (
    echo Copying icon file...
    copy "%~dp0icon.ico" "%INSTALL_PATH%\SmartOPD\icon.ico" >nul
)

:: สร้าง shortcut ของ start.bat ที่ Desktop
echo Creating desktop and startup shortcuts...
powershell -Command "$WS = New-Object -ComObject WScript.Shell; $SC = $WS.CreateShortcut('%userprofile%\Desktop\Smart Connect.lnk'); $SC.TargetPath = '%userprofile%\Desktop\SmartOPD_start.bat'; if (Test-Path '%INSTALL_PATH%\SmartOPD\icon.ico') { $SC.IconLocation = '%INSTALL_PATH%\SmartOPD\icon.ico' }; $SC.WorkingDirectory = '%INSTALL_PATH%\SmartOPD'; $SC.Save()"

:: สร้าง shortcut ใน Startup folder แบบ Run as Administrator
powershell -Command "$WS = New-Object -ComObject WScript.Shell; $SC = $WS.CreateShortcut('%appdata%\Microsoft\Windows\Start Menu\Programs\Startup\Smart Connect.lnk'); $SC.TargetPath = '%userprofile%\Desktop\SmartOPD_start.bat'; if (Test-Path '%INSTALL_PATH%\SmartOPD\icon.ico') { $SC.IconLocation = '%INSTALL_PATH%\SmartOPD\icon.ico' }; $SC.WorkingDirectory = '%INSTALL_PATH%\SmartOPD'; $SC.Save(); Start-Process powershell -Verb RunAs -ArgumentList '-Command', 'Set-ItemProperty -Path ''%appdata%\Microsoft\Windows\Start Menu\Programs\Startup\Smart Connect.lnk'' -Name Attributes -Value 32'"

echo ==============================
echo Installation complete!
echo ==============================
echo.
echo Program installed to: %INSTALL_PATH%
echo Shortcuts created on desktop
echo.
echo Please configure your database settings in config\dbConfig.json
echo and port settings in config\portConfig.json before starting the application.
echo.
pause 