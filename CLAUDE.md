## Commands

- run: `flutter run`
- deploy: `scripts/deploy.sh` (pulls ~/src/home_inventory, release build + phone_deploy to the Pixel, health check: installed APK hash = built APK, app running; Arch desktop package stays manual: `install_arch.sh` needs interactive sudo)
- test: `flutter test --reporter=compact`
- test-changed: `scripts/test_changed.sh`
- lint: `flutter analyze --fatal-infos --fatal-warnings`
- coverage: `flutter test --coverage --reporter=compact`
- coverage-gaps: `coverage-gaps coverage/lcov.info`
