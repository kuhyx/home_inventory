/// The fixed origin the desktop wrapper serves on.
library;

/// Port the desktop wrapper listens on.
///
/// **Do not change this casually.** IndexedDB (which holds the inventory log)
/// and `localStorage` are both keyed by origin, so changing the port silently
/// hides the user's entire local inventory behind an origin they no longer
/// visit. `bin/home_inventory_desktop.dart` and `install_arch.sh` must use the
/// same value.
///
/// 8733 because the sibling apps already own the ports below it: todo 8730,
/// and two others on 8731 and 8732. A collision would mean two apps fighting
/// for the same bind — and, worse, sharing an origin.
const desktopWrapperPort = 8733;

/// Origin of the desktop wrapper, e.g. `http://localhost:8733`.
const desktopWrapperOrigin = 'http://localhost:$desktopWrapperPort';
