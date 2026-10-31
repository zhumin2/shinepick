@echo off
setlocal
set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"
set "ANDROID_HOME=D:\Apps\android-sdk"
set "PATH=%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"
set "PUB_HOSTED_URL=https://pub.flutter-io.cn"
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"

cd /d D:\code\elive\shinepick\app
D:\Apps\flutter-sdk\flutter\bin\flutter.bat build apk --release --dart-define=API_BASE_URL=http://129.226.159.168:8080/api/v1
