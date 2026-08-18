// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored documents the engine is replayed against.
internal enum CorpusFile {
  private static let conformanceName = "rapp-v26.8.17.233.json"
  private static let transportName = "rapp-transport-v26.8.17.233.json"

  /// Test sources sit four directories below the repository root.
  private static let depthBelowRepositoryRoot = 4

  internal static func conformance(filePath: String) throws -> Corpus {
    try JSONDecoder().decode(
      Corpus.self, from: try data(named: conformanceName, filePath: filePath))
  }

  internal static func transport(filePath: String) throws -> TransportCorpus {
    try JSONDecoder().decode(
      TransportCorpus.self, from: try data(named: transportName, filePath: filePath))
  }

  private static func repositoryRoot(from filePath: String) -> URL {
    var url = URL(fileURLWithPath: filePath)
    for _ in 0..<depthBelowRepositoryRoot {
      url = url.deletingLastPathComponent()
    }
    return url
  }

  private static func data(named name: String, filePath: String) throws -> Data {
    try Data(
      contentsOf: repositoryRoot(from: filePath)
        .appendingPathComponent("Documentation/rapp-conformance")
        .appendingPathComponent(name))
  }
}
