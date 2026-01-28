@echo off
setlocal enabledelayedexpansion
set PASS=0
set FAIL=0
for %%f in (C:\dev\conway\arch-test\bin\*.elf) do (
    C:\dev\conway\test\compliance\conway_test.exe "%%f" >nul 2>&1
    if !errorlevel! equ 0 (
        echo PASS: %%~nf
        set /a PASS+=1
    ) else (
        echo FAIL: %%~nf ^(exit !errorlevel!^)
        set /a FAIL+=1
    )
)
echo.
echo Total: !PASS! passed, !FAIL! failed
