# Building Ham Net Manager as an AppImage

This document explains how to build a Linux AppImage for Ham Net Manager — a portable, self-contained executable that works across different Linux distributions.

## What is an AppImage?

An AppImage is a universal binary format for Linux applications. It bundles your application and its dependencies into a single `.AppImage` file that can be:
- Distributed via a simple download
- Run directly without installation (just `chmod +x` and run)
- Used on any Linux distribution (no dependency conflicts)

## Prerequisites

1. **Flutter SDK** installed and configured for Linux desktop
2. **appimagetool** — the tool that creates AppImages

### Installing appimagetool

On Debian/Ubuntu:
```bash
sudo apt install appimagetool
```

On Fedora:
```bash
sudo dnf install appimagetool
```

Or download directly from https://github.com/AppImage/AppImageKit/releases

## Building the AppImage

Run the build script:

```bash
./scripts/build_appimage.sh
```

This script will:
1. Build the Flutter Linux release (if not already built)
2. Create an AppDir structure with the binary, libraries, and assets
3. Add desktop integration files (icon, .desktop file)
4. Generate the AppImage using `appimagetool`

The resulting AppImage will be created in `dist/Ham_Net_Manager-<version>-x86_64.AppImage`

## Running the AppImage

Once built, you can run it directly:

```bash
./dist/Ham_Net_Manager-1.0.0-x86_64.AppImage
```

Or make it executable and run it:

```bash
chmod +x dist/Ham_Net_Manager-1.0.0-x86_64.AppImage
./dist/Ham_Net_Manager-1.0.0-x86_64.AppImage
```

### Desktop Integration

The AppImage includes:
- A `.desktop` file for menu integration
- Icons in multiple resolutions (256x256, 512x512)

To permanently install it to your system:

```bash
cp dist/Ham_Net_Manager-1.0.0-x86_64.AppImage ~/.local/bin/
```

Or use `appimage-mount` to integrate it with your desktop environment.

## File Structure

The build creates:
- `build/appimage/ham_net_manager.AppDir/` — The AppDir directory structure
- `dist/Ham_Net_Manager-<version>-x86_64.AppImage` — The final AppImage executable

## How It Works

1. **Flutter Build**: `flutter build linux --release` creates the application bundle at `build/linux/x64/release/bundle/`

2. **AppDir Creation**: The script creates a standard Linux AppDir with:
   - `bin/` — Application binary
   - `lib/` — Libraries (libflutter_linux_gtk.so, libapp.so, libsqlite3.so, etc.)
   - `share/` — Data files, assets, icons, and desktop entry

3. **AppRun Script**: The `linux/AppRun` script sets up the runtime environment (LD_LIBRARY_PATH, etc.) and launches the application

4. **AppImage Creation**: `appimagetool` compresses the AppDir into a self-extracting, mountable AppImage file

## Troubleshooting

### "appimagetool not found"
Install it with your package manager (see Prerequisites section above)

### AppImage won't run on another machine
- Ensure you built on a system with older libc/glibc (older distributions have better compatibility)
- Or use a build container with an older Linux distribution

### Libraries not found at runtime
The AppRun script sets `LD_LIBRARY_PATH` automatically. If you see library errors:
1. Check that `lib/` contains all needed .so files
2. Verify the bundle was built correctly with `flutter build linux --release`

### Icon not showing
- Icons are included from macOS assets
- To customize, replace the icon files at: `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png`
- Then rebuild the AppImage

## Continuous Integration

To automate AppImage builds in CI/CD, add to your workflow:

```bash
./scripts/build_appimage.sh
```

The script is idempotent — you can run it multiple times and it will rebuild correctly.

## Distribution

Once you have the AppImage:

1. **Upload to GitHub Releases**: Users can download and run directly
2. **Host on a website**: Users download the file and run it
3. **Use AppImageHub**: Submit your AppImage to be listed on https://appimage.github.io

## Additional Resources

- [AppImage Documentation](https://docs.appimage.org/)
- [AppImageKit](https://github.com/AppImage/AppImageKit)
- [Flutter Desktop Linux Documentation](https://docs.flutter.dev/platform-integration/linux)
