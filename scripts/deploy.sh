#!/bin/bash
# Deploy home_inventory for real: pull the live checkout, release-build it and
# install it over the app on the Pixel with phone_deploy (adb install -r; never
# uninstall, never pm clear), then prove the phone runs exactly that APK.
#
#   scripts/deploy.sh
#
# Idempotent: every run pulls (no-op when current), rebuilds and reinstalls
# with data kept. Exits non-zero when the pull, the build/install (phone_deploy
# exit codes pass through) or the health check fails.
# Env: APP_DIR (default ~/src/home_inventory), ADB_SERIAL (default the Pixel),
#      PHONE_DEPLOY (default ~/.claude/scripts/phone_deploy.sh).
# The Arch desktop package needs interactive sudo (install_arch.sh), so it
# stays a manual step and is not part of this deploy.
set -euo pipefail

readonly APP_DIR="${APP_DIR:-$HOME/src/home_inventory}"
readonly SERIAL="${ADB_SERIAL:-23181JEGR08034}"
readonly PHONE_DEPLOY="${PHONE_DEPLOY:-$HOME/.claude/scripts/phone_deploy.sh}"
readonly PKG=com.kuhy.home_inventory
readonly APK="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

die() {
	echo "deploy.sh: FAIL: $*" >&2
	exit 1
}

step() {
	echo "deploy.sh: $*"
}

# phone_sh <cmd...>: one adb shell call on the Pixel, CR stripped.
phone_sh() {
	adb -s "$SERIAL" shell "$@" | tr -d '\r'
}

# health_check: the installed base.apk must be byte-identical to the APK just
# built, and the app process must be alive after phone_deploy launched it.
health_check() {
	local apk_path local_sum phone_sum pid
	[[ -f "$APK" ]] || die "no built APK at $APK"
	local_sum=$(sha256sum "$APK" | cut -d' ' -f1)
	apk_path=$(phone_sh pm path "$PKG" | sed -n 's/^package://p' | grep -m1 'base\.apk$') \
		|| die "$PKG not installed on $SERIAL"
	phone_sum=$(phone_sh sha256sum "$apk_path" | cut -d' ' -f1)
	[[ "$local_sum" == "$phone_sum" ]] \
		|| die "installed APK ($phone_sum) differs from the built one ($local_sum)"
	pid=$(phone_sh pidof "$PKG" || true)
	[[ -n "$pid" ]] || die "$PKG is not running after launch"
	step "healthy: installed APK sha256 $local_sum, pid $pid"
}

main() {
	adb -s "$SERIAL" get-state >/dev/null 2>&1 || die "phone $SERIAL unreachable"
	step "pull $APP_DIR"
	git -C "$APP_DIR" pull --ff-only || die "git pull --ff-only failed in $APP_DIR"
	step "release build + install ($(git -C "$APP_DIR" rev-parse --short HEAD))"
	local shot_dir rc=0
	shot_dir=$(mktemp -d)
	ADB_SERIAL="$SERIAL" bash "$PHONE_DEPLOY" "$APP_DIR" --release --shot "$shot_dir/shot.png" || rc=$?
	rm -rf -- "$shot_dir"
	if ((rc != 0)); then
		echo "deploy.sh: FAIL: phone_deploy exited $rc" >&2
		exit "$rc"
	fi
	health_check
}

main "$@"
