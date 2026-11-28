## Commands

- run: `flutter run`
- deploy: `git -C ~/src/home_inventory pull --ff-only && ~/src/home_inventory/scripts/deploy.sh` (release build + phone_deploy to the Pixel, health check: installed APK hash = built APK, app running; Arch desktop package stays manual: `install_arch.sh` needs interactive sudo)
- test: `flutter test --reporter=compact`
- test-changed: `scripts/test_changed.sh`
- lint: n/a: dropped (kuhy, 2026-11-27)
- coverage: n/a: dropped (kuhy, 2026-11-27)
- coverage-gaps: n/a: dropped (kuhy, 2026-11-27)
