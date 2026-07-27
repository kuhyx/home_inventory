import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Stands in for the system file dialogs.
///
/// Faked through the platform interface rather than `coverage:ignore`d, so the
/// export and import paths run their real code — including the cancellation
/// branches, which are the ones a manual test never bothers to take.
class FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  /// What the save dialog returns; null stands for a cancelled dialog.
  FileSaveLocation? saveLocation;

  /// What the open dialog returns; null stands for a cancelled dialog.
  XFile? fileToOpen;

  /// Every save dialog the code under test asked for.
  final List<String?> saveRequests = [];

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    saveRequests.add(options.suggestedName);
    return saveLocation;
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => fileToOpen;
}
