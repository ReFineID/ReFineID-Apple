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
import Testing

/// Exercises the trace's trimming rule.
///
/// Only the rule is tested, not the keychain around it: storage needs an
/// entitlement this bundle does not carry, and the rule is where a mistake
/// would actually live. The mistake that matters is cutting the wrong end
/// -- a trace that kept the OLDEST lines would answer every question with
/// the state from before the run being measured.
@Suite
internal struct ExtensionTraceTests {
  /// Separates two lines in the stored blob.
  private static let separator = "\n"

  /// A line long enough that a few hundred of them overflow the cap.
  private static let filler = String(repeating: "x", count: 100)

  /// How many lines are needed to overflow the cap several times over.
  private static let overflowingLineCount = 400

  /// `lineCount` numbered lines, oldest first.
  private static func buffer(lineCount: Int) -> String {
    (0..<lineCount)
      .map { "\($0) " + Self.filler }
      .joined(separator: Self.separator)
  }

  @Test
  internal func aBufferInsideTheCapIsKeptWhole() {
    let short = Self.buffer(lineCount: 3)
    #expect(ExtensionTrace.trimmed(short) == short)
  }

  @Test
  internal func anEmptyBufferStaysEmpty() {
    #expect(ExtensionTrace.trimmed("").isEmpty)
  }

  @Test
  internal func anOverfullBufferIsCutToTheCap() {
    let overfull = Self.buffer(lineCount: Self.overflowingLineCount)
    #expect(overfull.utf8.count > ExtensionTrace.maximumBytes)
    #expect(ExtensionTrace.trimmed(overfull).utf8.count <= ExtensionTrace.maximumBytes)
  }

  @Test
  internal func theNewestLinesAreTheOnesKept() {
    let overfull = Self.buffer(lineCount: Self.overflowingLineCount)
    let kept = ExtensionTrace.trimmed(overfull)
    #expect(kept.hasSuffix("\(Self.overflowingLineCount - 1) " + Self.filler))
    #expect(!kept.hasPrefix("0 "))
  }

  @Test
  internal func oneUnsplittableLineIsLeftAlone() {
    // Nothing to cut on: refusing to truncate mid-line keeps the trace
    // readable rather than trading a whole line for a byte count.
    let single = String(repeating: "y", count: ExtensionTrace.maximumBytes + 1)
    #expect(ExtensionTrace.trimmed(single) == single)
  }
}
