@echo off
chcp 65001 >nul
title MkDocs 一键部署工具

REM ========== 代理配置（仅本次运行生效）==========
REM 将下面的 yes 改为 no 可禁用代理
set USE_PROXY=yes
set HTTP_PROXY=http://127.0.0.1:7897
set HTTPS_PROXY=http://127.0.0.1:7897
REM ===============================================

echo ========================================
echo    MkDocs 博客一键部署脚本
echo ========================================
echo.

REM 检查目录
if not exist "mkdocs.yml" (
    echo [错误] 请在 MkDocs 项目根目录运行此脚本！
    pause
    exit /b 1
)

REM 启用临时代理（仅当前脚本和子进程生效）
if /i "%USE_PROXY%"=="yes" (
    set http_proxy=%HTTP_PROXY%
    set https_proxy=%HTTPS_PROXY%
    echo [√] 临时代理已启用: %HTTP_PROXY%
    echo [√] 仅本次脚本运行使用，不影响系统
    echo.
)

REM 提交源码
echo [1/2] 提交源码到 main 分支...
git add .
git commit -m "[update] 更新博客内容"
git push origin main
if errorlevel 1 (
    echo [错误] 推送失败！
    pause
    exit /b 1
)
echo [√] 源码提交成功
echo.

REM 部署网站
echo [2/2] 部署到 gh-pages 分支...
mkdocs gh-deploy
if errorlevel 1 (
    echo [错误] 部署失败！
    pause
    exit /b 1
)
echo [√] 部署成功
echo.

echo ========================================
echo 部署完成！
echo 网站: https://crootkit.github.io/
echo ========================================
pause