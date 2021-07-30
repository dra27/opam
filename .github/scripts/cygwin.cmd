@rem ***********************************************************************
@rem *                                                                     *
@rem *     Copyright 2021 David Allsopp Ltd.                               *
@rem *                                                                     *
@rem *  All rights reserved. This file is distributed under the terms of   *
@rem *  the GNU Lesser General Public License version 2.1, with the        *
@rem *  special exception on linking described in the file LICENSE.        *
@rem *                                                                     *
@rem ***********************************************************************
@setlocal
@echo off

:: This script configures Cygwin32 or Cygwin64 either from a cached copy or by
:: downloading the Cygwin Setup program.
::
:: cygwin.cmd distro
::
:: where distro is cygwin32 or cygwin64
::
:: Environment variables:
::   CYGWIN32_CACHE_DIR - location of Cygwin32 cache files
::   CYGWIN64_CACHE_DIR - location of Cygwin64 cache files
::   CYGWIN_ROOT        - Cygwin installation root directory
::   CYGWIN_MIRROR      - Package repository mirror

if "%1" equ "cygwin32" (
  set CYGWIN_CACHE_DIR=%CYGWIN32_CACHE_DIR%
) else (
  if "%1" equ "cygwin64" (
    set CYGWIN_CACHE_DIR=%CYGWIN64_CACHE_DIR%
  ) else (
    echo Invalid Cygwin distro: %1
    exit /b 2
  )
)

if not exist %CYGWIN_CACHE_DIR%\cache.tar call :SetupCygwin %1

if not exist %CYGWIN_ROOT%\setup.exe call :RestoreCygwin

set PATH=%CYGWIN_ROOT%\bin;%PATH%
echo %CYGWIN_ROOT%\bin>> %GITHUB_PATH%

goto :EOF

:SetupCygwin

echo ::group::Installing Cygwin

if exist %CYGWIN_ROOT%\nul rd /s/q %CYGWIN_ROOT%
md %CYGWIN_ROOT%

set CYGWIN_PACKAGES=make,patch,curl,diffutils,tar,unzip,git,gcc-g++,flexdll
if "%1" equ "cygwin64" (
  set CYGWIN_PACKAGES=%CYGWIN_PACKAGES%,mingw64-i686-gcc-g++,mingw64-x86_64-gcc-g++
  curl -Lo %CYGWIN_ROOT%\setup.exe https://cygwin.com/setup-x86_64.exe
) else (
  curl -Lo %CYGWIN_ROOT%\setup.exe https://cygwin.com/setup-x86.exe
)

%CYGWIN_ROOT%\setup.exe --quiet-mode --no-shortcuts --no-startmenu --no-desktop --only-site --root %CYGWIN_ROOT% --site "%CYGWIN_MIRROR%" --local-package-dir D:\cygwin-packages --packages %CYGWIN_PACKAGES%

:: This triggers the first-time copying of the skeleton files for the user.
:: The main reason for doing this is so that the noise on stdout doesn't mess
:: up the call to ldd later!
%CYGWIN_ROOT%\bin\bash -lc "uname -a"

echo ::endgroup::

for /f "delims=" %%P in ('%CYGWIN_ROOT%\bin\cygpath.exe %CYGWIN_ROOT:~0,2%') do set CYGWIN_ROOT_NATIVE=%%P
for /f "delims=" %%P in ('%CYGWIN_ROOT%\bin\cygpath.exe "%CYGWIN_ROOT_NATIVE%%CYGWIN_ROOT:~2%"') do set CYGWIN_ROOT_NATIVE=%%P
for /f "delims=" %%P in ('%CYGWIN_ROOT%\bin\cygpath.exe %CYGWIN_CACHE_DIR%') do set CYGWIN_CACHE_DIR_NATIVE=%%P

echo Cygwin installed in %CYGWIN_ROOT% ^(%CYGWIN_ROOT_NATIVE%^)
echo Cygwin cache maintained at %CYGWIN_CACHE_DIR% ^(%CYGWIN_CACHE_DIR_NATIVE%^)

:: XXX Document this COMBAK

if not exist %CYGWIN_CACHE_DIR%\bootstrap\nul md %CYGWIN_CACHE_DIR%\bootstrap

echo Setting up bootstrap process...
echo   - tar.exe
copy %CYGWIN_ROOT%\bin\tar.exe %CYGWIN_CACHE_DIR%\bootstrap\ > nul
echo ./bin/tar.exe> D:\exclude

for /f "usebackq delims=" %%f in (`%CYGWIN_ROOT%\bin\bash -lc "ldd /bin/tar | sed -ne 's|.* => \(/usr/bin/.*\) ([^)]*)$|\1|p' | xargs cygpath -w"`) do (
  echo   - %%f
  echo ./bin/%%~nxf>> D:\exclude
  copy %%f %CYGWIN_CACHE_DIR%\bootstrap\ > nul
)

%CYGWIN_ROOT%\bin\bash -lc "tar -pcf %CYGWIN_CACHE_DIR_NATIVE%/cache.tar --exclude-from=/cygdrive/d/exclude -C %CYGWIN_ROOT_NATIVE% ."
echo %CYGWIN_ROOT_NATIVE%> %CYGWIN_CACHE_DIR%\restore

del D:\exclude

goto :EOF

:RestoreCygwin

pushd %CYGWIN_CACHE_DIR%

if not exist %CYGWIN_ROOT%\bin\nul md %CYGWIN_ROOT%\bin
copy bootstrap\* %CYGWIN_ROOT%\bin\
for /f "delims=" %%P in (restore) do set CYGWIN_ROOT_NATIVE=%%P
tar -pxf cache.tar -C %CYGWIN_ROOT_NATIVE%

popd

goto :EOF
