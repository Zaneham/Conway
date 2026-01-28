@echo off
cd /d C:\dev\conway
echo Testing with no args (uses default path)...
test\compliance\conway_test_new.exe
echo Exit code: %ERRORLEVEL%
