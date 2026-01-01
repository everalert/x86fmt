@echo off

:: helper for removing stale zig build artifacts. only necessary with a batch 
:: script on windows, because this is achievable from within the zig build system 
:: on other platforms.

if exist .zig-cache    rmdir /s /q .zig-cache
if exist .zig-out      rmdir /s /q .zig-out
if exist zig-cache     rmdir /s /q zig-cache
if exist zig-out       rmdir /s /q zig-out
