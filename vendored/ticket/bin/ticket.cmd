@echo off
setlocal
set "SCRIPT=%~dp0ticket.sh"
set "SCRIPT=%SCRIPT:\=/%"
set "GIT_BASH=C:\Program Files\Git\usr\bin\bash.exe"
if not exist "%GIT_BASH%" (
  echo Error: Git bash not found >&2
  exit /b 1
)
rem Forward the script as a program argument and pass the original argument
rem tail as separate tokens. Do NOT interpolate %* into a bash -c string:
rem embedded quotes would terminate the -c argument early and word-split args.
"%GIT_BASH%" --login "%SCRIPT%" %*
exit /b %ERRORLEVEL%