# Ham Net Manager

A Flutter application for managing ham radio nets on Linux and Windows desktop platforms.

## Installation
### Linux
```bash
sudo wget https://github.com/hestela/ham_net_manager/releases/latest/download/Ham_Net_Manager-1.0.0-x86_64.AppImage -O /usr/local/bin/ham_net_manager
sudo chmod +x /usr/local/bin/ham_net_manager
```

### Windows
For windows, you will either need to build the app yourself with flutter or you can download an MSIX release but then you will need to install the self-signed code signing certificate that was used to build this app.

## Quick Start
### Prerequisites
- Flutter 3.11+ (with desktop support enabled)
- For Linux: GTK 3.0+ development files
- For AppImage builds: `appimagetool`

### Building

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

### AppImage Distribution

Build a portable Linux AppImage:
```bash
./scripts/build_appimage.sh
```

This creates `dist/Ham_Net_Manager-*.AppImage` which can be:
- Distributed directly to users
- Run without installation
- Used on any Linux distribution

See [docs/APPIMAGE_BUILD.md](docs/APPIMAGE_BUILD.md) for details.

## Development

- **Flutter**: [Official docs](https://docs.flutter.dev/)
- **Project guidance**: See [CLAUDE.md](CLAUDE.md)
- **Database**: SQLite via `sqflite_common_ffi`

## Project Structure

- `lib/` — Dart/Flutter code
- `linux/` — Linux/GTK platform configuration and AppImage files
- `windows/` — Windows platform configuration
- `scripts/` — Build automation scripts
- `test/` — Test files

## Deployment

### Linux
- **Development**: `flutter run -d linux`
- **Release binary**: `flutter build linux --release` → `build/linux/x64/release/bundle/`
- **AppImage**: `./scripts/build_appimage.sh` → `dist/Ham_Net_Manager-*.AppImage`

### Windows
```bash
flutter build windows --release
```
