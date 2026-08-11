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

import CardCore
import Foundation
import Testing

/// The one-request-per-connection HTTP framing of the SCS exchange
/// (DVV SCS specification v1.3 §2.4).
@Suite
internal struct ScsHttpTests {
  @Test
  internal func assemblesAConcatenatedRequest() {
    let wire =
      "POST /sign HTTP/1.1\r\nOrigin: https://dvv.fineid.fi\r\n"
      + "Content-Type: application/json\r\nContent-Length: 4\r\n\r\nbody"
    let assembly = ScsHttpAssembly.assemble(buffer: Data(wire.utf8))
    guard case .complete(let exchange) = assembly else {
      Issue.record("expected a complete request")
      return
    }
    #expect(exchange.request.method == "POST")
    #expect(exchange.request.path == "/sign")
    #expect(exchange.request.origin == "https://dvv.fineid.fi")
    #expect(exchange.request.contentType == "application/json")
    #expect(exchange.body == Data("body".utf8))
  }

  @Test
  internal func waitsForTheWholeBody() {
    let wire = "POST /sign HTTP/1.1\r\nContent-Length: 10\r\n\r\nhalf"
    #expect(ScsHttpAssembly.assemble(buffer: Data(wire.utf8)) == .needMoreData)
  }

  @Test
  internal func waitsForTheHeadBoundary() {
    #expect(
      ScsHttpAssembly.assemble(buffer: Data("GET /version HTTP/1.1\r\n".utf8))
        == .needMoreData)
  }

  @Test
  internal func stripsTheQueryString() {
    let wire = "GET /version?probe=1 HTTP/1.1\r\n\r\n"
    let assembly = ScsHttpAssembly.assemble(buffer: Data(wire.utf8))
    guard case .complete(let exchange) = assembly else {
      Issue.record("expected a complete request")
      return
    }
    #expect(exchange.request.path == "/version")
  }

  @Test
  internal func responsesEchoTheOriginAndClose() throws {
    let response = ScsHttpResponse.json(
      status: 200,
      body: Data("{}".utf8),
      origin: "https://dvv.fineid.fi"
    )
    let text = try #require(String(data: response, encoding: .utf8))
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Access-Control-Allow-Origin: https://dvv.fineid.fi\r\n"))
    #expect(text.contains("Connection: close\r\n"))
    #expect(text.contains("Content-Length: 2\r\n"))
    #expect(text.hasSuffix("\r\n\r\n{}"))
  }

  @Test
  internal func preflightAnswersOkWithCors() throws {
    let response = ScsHttpResponse.preflight(origin: "https://dvv.fineid.fi")
    let text = try #require(String(data: response, encoding: .utf8))
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Access-Control-Allow-Methods: GET, POST\r\n"))
  }
}
