@echo off
echo [sudo] Building SudoWindows...
echo.

REM Clean previous builds
if exist "bin" rmdir /s /q bin
if exist "obj" rmdir /s /q obj
if exist "publish" rmdir /s /q publish

REM Build self-contained single-file executable
dotnet publish ^
    -c Release ^
    -r win-x64 ^
    --self-contained true ^
    -p:PublishSingleFile=true ^
    -p:IncludeNativeLibrariesForSelfExtract=true ^
    -p:EnableCompressionInSingleFile=true ^
    -o publish

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [sudo] BUILD FAILED
    exit /b 1
)

echo.
echo [sudo] Build complete!
echo [sudo] Output: publish\SudoWindows.exe
echo.
dir publish\SudoWindows.exe
