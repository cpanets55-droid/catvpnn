@echo off
setlocal
set "SDK_ROOT=C:\Users\Admin\catvp-sdk"
set "JAVA_HOME=%SDK_ROOT%\jdk"
set "ANDROID_HOME=%SDK_ROOT%\android-sdk"
set "ANDROID_SDK_ROOT=%SDK_ROOT%\android-sdk"
set "PATH=%SDK_ROOT%\flutter\bin;%SDK_ROOT%\git\cmd;%SDK_ROOT%\jdk\bin;%SDK_ROOT%\android-sdk\cmdline-tools\latest\bin;%SDK_ROOT%\android-sdk\platform-tools;%PATH%"

cd /d "%~dp0"
echo [CatVPN Nord] Dang build APK Release (arm64-v8a) va cai len dien thoai...
call flutter build apk --release --target-platform android-arm64
if errorlevel 1 (
    echo [LOI] Build that bai!
    pause
    exit /b 1
)

adb install -r "build\app\outputs\flutter-apk\app-release.apk"
adb shell monkey -p com.catvpn.nord.catvp -c android.intent.category.LAUNCHER 1
echo [HOAN TAT] Da cai va mo CatVPN Nord tren dien thoai!
pause
