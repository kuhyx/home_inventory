/// The one value every form validator returns for a bad field.
library;

/// A validator's "invalid" result.
///
/// Textgate: non-null, so the form refuses to save and the field draws its
/// thick error-coloured border (see `buildDarkTheme`), but empty, so no
/// sentence is painted under it. The border shape and colour are the cue.
const String invalidField = '';
