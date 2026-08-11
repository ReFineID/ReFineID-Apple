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

/// A small command-line benchmark for the hot arithmetic used by PACE.
///
/// Compile this file in the same module as CardCore so internal fixed-width
/// constants remain available:
///
///     swiftc -O -whole-module-optimization \
///       CardCore/Sources/CardCore/**/*.swift \
///       Scripts/BrainpoolBenchmark.swift \
///       -o /tmp/refineid-brainpool-benchmark
///
///     /tmp/refineid-brainpool-benchmark
@main
private enum BrainpoolBenchmark {
  /// Enough samples to show warm performance without making the run slow.
  private static let sampleCount = 9

  /// Unit conversions for a `Duration.Components` value.
  private static let millisecondsPerSecond = 1_000.0
  private static let attosecondsPerMillisecond = 1_000_000_000_000_000.0

  /// The repeated byte forming the benchmark scalar.
  private static let scalarByte: UInt8 = 90

  /// A fixed 383-bit scalar, so every sample exercises the full loop.
  private static let scalar: U384 = {
    guard
      let value = U384(
        bigEndianBytes: Data(repeating: scalarByte, count: U384.byteCount)
      )
    else {
      fatalError("The fixed-width benchmark scalar could not be constructed")
    }
    return value
  }()

  static func main() {
    for sample in 0..<sampleCount {
      let start = ContinuousClock.now
      let point = BrainpoolP384r1.multiplyGenerator(by: scalar)
      let elapsed = start.duration(to: .now)
      guard let marker = point.encodeUncompressed()?.last else {
        fatalError("A nonzero scalar unexpectedly produced infinity")
      }
      let milliseconds =
        Double(elapsed.components.seconds) * millisecondsPerSecond
        + Double(elapsed.components.attoseconds) / attosecondsPerMillisecond
      print("\(sample): \(milliseconds) ms [\(marker)]")
    }
  }
}
