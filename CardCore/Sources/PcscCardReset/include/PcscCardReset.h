#include <stdbool.h>

/// Resets the card in the named PC/SC reader, making the system
/// re-evaluate what the card is.
///
/// C, because the PCSC module is marked unimportable from Swift while
/// its C interface remains fully supported.
///
/// Returns true when the reset went through.
bool CardCoreResetCard(const char *readerName);
