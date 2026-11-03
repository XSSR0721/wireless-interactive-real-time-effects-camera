@echo off
chcp 65001 >nul
pushd "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 photo_receiver.py %*
) else (
  where python >nul 2>nul
  if errorlevel 1 (
    echo 未找到 Python。请安装带 Tkinter 的 Python 3，然后重新运行本文件。
    pause
    exit /b 1
  )
  python photo_receiver.py %*
)
if errorlevel 1 pause
popd
