# Ham Net Manager

A Flutter application for managing ham radio nets on Linux and Windows desktop platforms.  
Each Net is contained within a sqlite database file and can be imported/exported or overwritten so that you can share the database file after checking-in people to your net.  
Multiple Nets are supported, can switch between nets when launching the app or after selecting a different net.  
Some persistent infromation is saved in "Your Info" to be used for template variables in the net control script.  
Each net can have its own net control script writen in markdown, most syntax is supported including tables.  
Each net contains a list of members and information about them as needed. Fuzzy search for members is enabled in the main check-in UI and in the member management.  

## Installation
### Linux
```bash
sudo wget https://github.com/hestela/ham_net_manager/releases/latest/download/Ham_Net_Manager-1.0.0-x86_64.AppImage -O /usr/local/bin/ham_net_manager
sudo chmod +x /usr/local/bin/ham_net_manager
```

### Windows
For windows, you will either need to build the app yourself with flutter or you can download an MSIX release but then you will need to install the self-signed code signing certificate that was used to build this app.
#### MSIX Install
You will need to "trust" the self-signed certificate that was used to build the MSIX file. You only need to do this once, unless the certificate gets updated.
1. Download the certificate by [clicking here (github link)](https://github.com/hestela/ham_net_manager/raw/refs/heads/main/ham_net_manager.cer)
2. Double-click ham_net_manager.cer
3. "Install Certificate"
4. Select Local Machine
5. "Place all certificates in the following store"
6. Browse
7. Trusted People
8. OK

Now you can install the latest MSIX file.
[Download Latest Windows Release](https://github.com/hestela/ham_net_manager/releases/latest/download/ham_net_manager.msix)
In Windows 11 you can simply double click this file and it will ask if you want to install.
For Windows 10, you will need to open powershell and either cd to the folder with the download, or put the full path to the MSIX file.  
```powershell
Add-AppPackage -Path .\Ham_Net_Manager-1.0.0.msix
```

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

## Screenshots / Manual
Interface at startup:
- Can create a new net/database 
- Remove and optionally delete a net
![Startup](screenshots/startup.webp)

Main interface, buttons on the top right are:
- export current check-ins for active date to csv
- manage cities
- manage members/vistors
![Main UI](screenshots/main-ui.webp)

Net Control Script:
- Click the net control script button to show/hide
- Written with markdown
- Supports a few template variables (like your name, callsign and net name) so that you can substitute your callsign into the net control script.
- Click on the pencil icon to edit the script, script is unique to each city/database
![Net Control Script](screenshots/main-ui.webp)

Manage Cities:
![Manage Cities](screenshots/city-manager.webp)
- Add/remove Cities and Neighborhoods
- Cities and Nighborhoods are optional fields for the member information

Manage Members:
![Manage Members](screenshots/member-manager.webp)
- Fuzzy search on all fields (click esc to clear search)
- "Members" have a star next to their name and Guests/Visitors have the person icon.
- add/remove/edit members here
- can import/export member information via csv
- When importing members, missing cities/neighborhoods will be created. Make sure that your city and neighborhood names don't have typos or small variations otherwise you will have duplicates.

Navigation Menu:
the icon at the top left of the main check-in UI has a so called "hamburger menu" (the 3 stacked lines) which has:
- Your Info (used for net control script mainly)
- Rename Net
- New Database (for new net)
- Switch Database (switch to previously setup net)
- Save Database As (to export sqlite database to a new location)
- Remove current database (to remove current net from history and optionally delete sqlite database file)
![Navigation](screenshots/navigation.webp)

Switch Database/Net:
![Switch Net](screenshots/switch-net.webp)

Your Info:
All fields are optional. This data persists between sessions and nets (it is stored in its own json file).
![Your Info](screenshots/your-info.webp)
