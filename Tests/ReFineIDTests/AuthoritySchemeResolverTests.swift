//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
import Testing

@testable import ReFineID

/// Direct checks for authority-address syntax before any network probe.
@Suite
internal struct AuthoritySchemeResolverTests {
  /// Exact HTTP and HTTPS URLs with a host are accepted, including an
  /// uppercase scheme as URL syntax permits.
  @Test
  internal func httpFamilyAddressesAreUsable() {
    #expect(AuthoritySchemeResolver.isUsable("http://timestamp.example"))
    #expect(AuthoritySchemeResolver.isUsable("HTTPS://timestamp.example/path"))
  }

  /// Scheme lookalikes, unrelated schemes, and missing hosts are not
  /// addresses the timestamp client may use.
  @Test
  internal func otherAddressShapesAreNotUsable() {
    for address in [
      "timestamp.example",
      "httpish://timestamp.example",
      "file:///tmp/timestamp",
      "https:/missing-host",
    ] {
      #expect(!AuthoritySchemeResolver.isUsable(address))
    }
  }
}
