.PHONY: help build-linux build-appimage build-windows-installer clean run analyze test sync-version bump-patch bump-minor bump-major

help:
	@echo "Ham Net Manager - Build Commands"
	@echo "=================================="
	@echo ""
	@echo "Development:"
	@echo "  make run                      - Run the app on Linux desktop"
	@echo "  make analyze                  - Run Flutter analyzer (linting)"
	@echo "  make test                     - Run tests"
	@echo ""
	@echo "Building:"
	@echo "  make build-linux              - Build Linux GTK binary"
	@echo "  make build-appimage           - Build Linux AppImage (requires appimagetool)"
	@echo "  make build-windows-installer  - Build Windows EXE installer via Inno Setup (run on Windows)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean                    - Remove build artifacts"
	@echo ""
	@echo "Versioning:"
	@echo "  make bump-patch               - Bump patch version (1.2.3 -> 1.2.4)"
	@echo "  make bump-minor               - Bump minor version (1.2.3 -> 1.3.0)"
	@echo "  make bump-major               - Bump major version (1.2.3 -> 2.0.0)"
	@echo ""

sync-version:
	./scripts/sync_version.sh

bump-patch:
	./scripts/sync_version.sh --patch

bump-minor:
	./scripts/sync_version.sh --minor

bump-major:
	./scripts/sync_version.sh --major

run: sync-version
	flutter run -d linux

build-linux: sync-version
	flutter build linux --release
	@echo ""
	@echo "✓ Linux build complete at: build/linux/x64/release/bundle/"

build-appimage: sync-version
	@command -v appimagetool >/dev/null 2>&1 || \
		{ echo "Error: appimagetool not found"; echo "Install with: sudo apt install appimagetool"; exit 1; }
	./scripts/build_appimage.sh

build-windows-installer: sync-version
	powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1

analyze:
	flutter analyze

test:
	flutter test

clean:
	flutter clean
	rm -rf build/ dist/
