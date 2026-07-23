/// Why a binary read failed.
///
/// Unknown card behavior stays typed instead of degrading into a
/// partial result.
public enum BinaryReadFailure: Equatable, Sendable {
  /// The file produced no bytes at all.
  case emptyFile

  /// The card returned more bytes than the chunk requested - a protocol
  /// violation; the accumulated data cannot be trusted.
  case oversizedChunk

  /// The card answered something other than success or end-of-file.
  case unexpectedStatus(StatusWord)
}
