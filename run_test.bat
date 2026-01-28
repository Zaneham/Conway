@echo off
cd /d C:\dev\emulators\conway
echo Testing with no args (uses default path)...
test\compliance\conway_test.exe
echo Exit code: %ERRORLEVEL%
