@echo off
REM Conway - Build script for Windows using MinGW
REM Requires: NASM (https://nasm.us) and MinGW-w64 (gcc)

setlocal enabledelayedexpansion

echo Conway - RISC-V to x86-64 Binary Translator
echo ============================================
echo (MinGW build)
echo.

REM Check for NASM
where nasm >nul 2>&1
if errorlevel 1 (
    echo ERROR: NASM not found. Install from https://nasm.us
    echo   or: choco install nasm
    exit /b 1
)

REM Check for GCC (MinGW)
where gcc >nul 2>&1
if errorlevel 1 (
    echo ERROR: GCC not found. Install MinGW-w64:
    echo   choco install mingw
    echo   or: https://www.mingw-w64.org/
    exit /b 1
)

REM Create directories
if not exist obj mkdir obj
if not exist bin mkdir bin

echo Compiling C...
gcc -Wall -Wextra -O2 -Iinclude -c -o obj/main.obj src/main.c
if errorlevel 1 (
    echo ERROR: Failed to compile main.c
    exit /b 1
)

echo Assembling...

REM Assemble each source file (no entry_win.asm -- replaced by main.c)
for %%f in (translator.asm elf_loader.asm platform_win.asm) do (
    echo   %%f
    nasm -f win64 -g -DWINDOWS -Iinclude/ -o obj/%%~nf.obj src/%%f
    if errorlevel 1 (
        echo ERROR: Failed to assemble %%f
        exit /b 1
    )
)

echo Linking with GCC...
gcc -o bin/conway.exe obj/main.obj obj/translator.obj obj/elf_loader.obj obj/platform_win.obj -lkernel32

if errorlevel 1 (
    echo ERROR: Linking failed
    exit /b 1
)

echo.
echo Build successful: bin\conway.exe
echo.
echo Try it: bin\conway.exe examples\hello.elf
