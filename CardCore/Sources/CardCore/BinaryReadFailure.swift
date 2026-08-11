// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

/// Why a binary read failed.
///
/// Unknown card behavior stays typed instead of degrading into a
/// partial result.
public enum BinaryReadFailure: Equatable, Sendable {
  /// The file produced no bytes at all.
  case emptyFile

  /// The object's own header declares more bytes than this read permits.
  case objectTooLarge

  /// The card returned more bytes than the chunk requested - a protocol
  /// violation; the accumulated data cannot be trusted.
  case oversizedChunk

  /// The card answered something other than success or end-of-file.
  case unexpectedStatus(StatusWord)
}
