# How to build
## Prerequisites
- Flutter 3.11+ (with desktop support enabled)
- For Linux: GTK 3.0+ development files
- For AppImage builds: `appimagetool`

# Linux
Using Make:
```bash
make build-linux       # Build Linux binary
make build-appimage    # Build AppImage for distribution
make run               # Run the app locally
```

Or with Flutter directly:
```bash
flutter pub get
flutter run -d linux
flutter build linux --release
```

## AppImage
Build a portable Linux AppImage:
```bash
./scripts/build_appimage.sh
```

This creates `dist/Ham_Net_Manager-*.AppImage`.

See [APPIMAGE_BUILD.md](APPIMAGE_BUILD.md) for details.

# Windows
```powershell
flutter build windows
```

Build msix app file:
```powershell
.\scripts\build_msix.ps1
```

Build installer exe:
```powershell
.\scripts\build_windows_installer.ps1
```

# Web
```bash
flutter run -d Chrome
```