@echo off
REM Conway - Build script for Windows
REM Requires: NASM (https://nasm.us) and GoLink (http://godevtool.com)

setlocal enabledelayedexpansion

echo Conway - RISC-V to x86-64 Binary Translator
echo ============================================
echo.

REM Check for NASM
where nasm >nul 2>&1
if errorlevel 1 (
    echo ERROR: NASM not found. Install from https://nasm.us
    echo   or: choco install nasm
    exit /b 1
)

REM Check for GoLink
where golink >nul 2>&1
if errorlevel 1 (
    echo ERROR: GoLink not found. Download from http://godevtool.com
    exit /b 1
)

REM Create directories
if not exist obj mkdir obj
if not exist bin mkdir bin

echo Assembling...

REM Assemble each source file
for %%f in (translator.asm elf_loader.asm platform_win.asm) do (
    echo   %%f
    nasm -f win64 -g -DWINDOWS -Iinclude/ -o obj/%%~nf.obj src/%%f
    if errorlevel 1 (
        echo ERROR: Failed to assemble %%f
        exit /b 1
    )
)

echo Linking...
golink /console /entry:main kernel32.dll /out:bin/conway.exe obj/translator.obj obj/elf_loader.obj obj/platform_win.obj

if errorlevel 1 (
    echo ERROR: Linking failed
    exit /b 1
)

echo.
echo Build successful: bin\conway.exe
echo.
echo Try it: bin\conway.exe examples\hello.elf
