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
/// Why a PDF could not be prepared or signed.
public enum PdfSigningError: Error, Equatable {
  /// A cross-reference or object stream uses a filter or predictor
  /// this reader does not decode.
  case crossReferenceStreamUnsupported

  /// The document is encrypted; this writer will not touch it.
  case encrypted

  /// The bytes do not begin as a PDF.
  case notAPdf

  /// The assembled structure outgrew its reserved hole; the hole
  /// cannot be resized after the byte ranges are fixed.
  case signatureTooLarge(needed: Int, reserved: Int)

  /// The catalog, page tree or trailer could not be followed.
  case structureUnreadable
}
