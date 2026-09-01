@echo off
REM ============================================================
REM Build script for godot-box3d with Tripofobia patches (M2)
REM ============================================================
REM 
REM Usage: Just run this script from anywhere (it changes dir internally).
REM It will:
REM   1. Configure MSVC environment (x64, Release)
REM   2. Configure cmake build directory (tools\box3d\build\)
REM   3. Build godot-box3d.dll in Release mode
REM   4. Copy the .dll to addons\godot-box3d\bin\
REM
REM Backups of original binaries live in addons\godot-box3d\bin\original\
REM
REM Tested with:
REM   - cmake 4.3.2
REM   - MSVC 14.44.35207 (Visual Studio Build Tools 2022)
REM   - Godot 4.4+
REM ============================================================

setlocal enabledelayedexpansion

REM --- Configuration ---
set "SCRIPT_DIR=%~dp0"
set "SOURCE_DIR=%SCRIPT_DIR%godot-box3d-src"
set "BUILD_DIR=%SCRIPT_DIR%build"
set "ADDON_BIN_DIR=%SCRIPT_DIR%..\..\addons\godot-box3d\bin"
set "MSVC_VERSION=14.44.35207"
set "VCVARSALL=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"

echo.
echo ============================================================
echo Building godot-box3d with Tripofobia patches
echo ============================================================
echo Source:      %SOURCE_DIR%
echo Build dir:   %BUILD_DIR%
echo Output bin:  %ADDON_BIN_DIR%
echo.

REM --- Verify prerequisites ---
if not exist "%SOURCE_DIR%\CMakeLists.txt" (
    echo ERROR: Source not found at %SOURCE_DIR%
    echo Run "git clone --recursive https://github.com/bearlikelion/godot-box3d.git %SOURCE_DIR%" first.
    exit /b 1
)

if not exist "%VCVARSALL%" (
    echo ERROR: vcvarsall.bat not found at "%VCVARSALL%"
    echo Adjust MSVC_VERSION in this script to match your installation.
    exit /b 1
)

REM --- Setup MSVC environment ---
echo Setting up MSVC environment...
call "%VCVARSALL%" x64 >nul
if errorlevel 1 (
    echo ERROR: Failed to initialize MSVC environment
    exit /b 1
)

REM --- Configure cmake ---
if not exist "%BUILD_DIR%" (
    echo Configuring cmake build directory...
    cmake -B "%BUILD_DIR%" -S "%SOURCE_DIR%" -G "Ninja" -DCMAKE_BUILD_TYPE=Release
    if errorlevel 1 (
        echo ERROR: cmake configuration failed
        exit /b 1
    )
) else (
    echo Build directory exists, re-running cmake configure to refresh...
    cmake -B "%BUILD_DIR%" -S "%SOURCE_DIR%" -G "Ninja" -DCMAKE_BUILD_TYPE=Release
    if errorlevel 1 (
        echo ERROR: cmake configuration failed
        exit /b 1
    )
)

REM --- Build ---
echo.
echo Building Release configuration (this may take several minutes)...
cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 (
    echo ERROR: Build failed
    exit /b 1
)

REM --- Copy .dll to addon bin ---
echo.
echo Copying built binaries to addon...
if not exist "%ADDON_BIN_DIR%\original" (
    echo NOTE: No backup found at %ADDON_BIN_DIR%\original - first build?
)

if exist "%BUILD_DIR%\godot-box3d.dll" (
    copy /Y "%BUILD_DIR%\godot-box3d.dll" "%ADDON_BIN_DIR%\godot-box3d.dll" >nul
    echo OK: godot-box3d.dll -> %ADDON_BIN_DIR%
) else if exist "%SOURCE_DIR%\bin\godot-box3d.dll" (
    copy /Y "%SOURCE_DIR%\bin\godot-box3d.dll" "%ADDON_BIN_DIR%\godot-box3d.dll" >nul
    echo OK: godot-box3d.dll ^(from source^): %ADDON_BIN_DIR%
) else (
    echo ERROR: Built dll not found
    echo Looked in: %BUILD_DIR%\godot-box3d.dll
    echo          : %SOURCE_DIR%\bin\godot-box3d.dll
    exit /b 1
)

if exist "%BUILD_DIR%\libgodot-box3d.so" (
    copy /Y "%BUILD_DIR%\libgodot-box3d.so" "%ADDON_BIN_DIR%\libgodot-box3d.so" >nul
    echo OK: libgodot-box3d.so -> %ADDON_BIN_DIR%
) else if exist "%SOURCE_DIR%\bin\libgodot-box3d.so" (
    copy /Y "%SOURCE_DIR%\bin\libgodot-box3d.so" "%ADDON_BIN_DIR%\libgodot-box3d.so" >nul
    echo OK: libgodot-box3d.so ^(from source^): %ADDON_BIN_DIR%
)

if exist "%BUILD_DIR%\libgodot-box3d.dylib" (
    copy /Y "%BUILD_DIR%\libgodot-box3d.dylib" "%ADDON_BIN_DIR%\libgodot-box3d.dylib" >nul
    echo OK: libgodot-box3d.dylib -> %ADDON_BIN_DIR%
) else if exist "%SOURCE_DIR%\bin\libgodot-box3d.dylib" (
    copy /Y "%SOURCE_DIR%\bin\libgodot-box3d.dylib" "%ADDON_BIN_DIR%\libgodot-box3d.dylib" >nul
    echo OK: libgodot-box3d.dylib ^(from source^): %ADDON_BIN_DIR%
)

echo.
echo ============================================================
echo Build complete! Restart Godot to load the new DLL.
echo ============================================================
echo.
echo Verify in Godot console:
echo   print^(PhysicsServer3D.get_class^(^)^)
echo Expected: "Box3D"
echo.

endlocal
