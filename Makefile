.PHONY: help build-linux build-appimage build-windows-installer clean run analyze test

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

run:
	flutter run -d linux

build-linux:
	flutter build linux --release
	@echo ""
	@echo "✓ Linux build complete at: build/linux/x64/release/bundle/"

build-appimage:
	@command -v appimagetool >/dev/null 2>&1 || \
		{ echo "Error: appimagetool not found"; echo "Install with: sudo apt install appimagetool"; exit 1; }
	./scripts/build_appimage.sh

build-windows-installer:
	powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1

analyze:
	flutter analyze

test:
	flutter test

clean:
	flutter clean
	rm -rf build/ dist/
