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
import Foundation

/// The transport a card session runs over.
///
/// One conforming value represents one exclusive card session; the
/// platform layer adapts `TKSmartCard` to this in a single line. Keeping
/// the protocol in CardCore lets every operation above it run against a
/// scripted fake in tests, with no hardware and no CryptoTokenKit.
public protocol CardChannel {
  /// The chunk a chunked read may ask this transport for.
  ///
  /// A read to end of file stops at the first chunk that comes back
  /// short, so the chunk has to be small enough that this transport can
  /// carry a full one home. Only the transport knows that, which is why
  /// the answer lives here rather than at the call site: a caller that
  /// had to remember would eventually forget, and the failure is a
  /// silently truncated certificate.
  ///
  /// There is deliberately no default implementation. Every transport
  /// states its own chunk, so a transport added later cannot inherit an
  /// answer that happens to be wrong for it -- it does not compile until
  /// somebody decides.
  var readChunkLength: ReadChunkLength { get }

  /// Sends one command APDU and returns the raw response bytes.
  func transmit(_ payload: Data) throws -> Data
}
