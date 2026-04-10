#!/bin/bash
# Run this after pulling from Git or making major pubspec changes
flutter pub get
dart run flutter_native_splash:create
# dart run build_runner build --delete-conflicting-outputs