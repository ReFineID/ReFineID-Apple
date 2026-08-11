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
#if os(macOS)

  import Foundation
  import Testing

  @testable import ReFineID

  /// RFC 9285 examples and malformed-input boundaries.
  @Suite
  internal struct Base45Tests {
    @Test(arguments: [
      ("AB", "BB8"),
      ("Hello!!", "%69 VD92EX0"),
      ("base-45", "UJCLQE7W581"),
      ("ietf!", "QED8WEX0"),
    ])
    internal func rfcExamples(plain: String, encoded: String) {
      #expect(Base45.encode(Data(plain.utf8)) == encoded)
      #expect(Base45.decode(encoded) == Data(plain.utf8))
    }

    @Test
    internal func malformedTextIsRefused() {
      #expect(Base45.decode("A") == nil)
      #expect(Base45.decode("abc") == nil)
      #expect(Base45.decode(":::") == nil)
    }

    @Test
    internal func everyByteRoundTrips() {
      let bytes = Data((UInt8.min...UInt8.max))

      #expect(Base45.decode(Base45.encode(bytes)) == bytes)
      #expect(Base45.decode(Base45.encode(Data())) == Data())
    }
  }

#endif
