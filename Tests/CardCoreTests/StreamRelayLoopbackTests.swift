// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The transport that replaces peer discovery with a published service and
/// a dialled port.
@Suite
internal struct StreamRelayLoopbackTests {

  // MARK: Static Properties

  private static let attempts = 100
  private static let pause = Duration.milliseconds(100)

  // MARK: Static Functions

  private static func awaitFrame(in mailbox: StreamRelayMailbox) async throws -> Data {
    for _ in 0..<attempts {
      if let frame = await mailbox.firstFrame { return frame }
      try await Task.sleep(for: pause)
    }
    throw StreamRelayTestFailure.noFrame
  }

  // MARK: Functions

  /// A dialer reaches a listener and each carries a frame to the other.
  ///
  /// This is the whole of what the nearby transport stopped doing between
  /// two devices: accept a connection and carry bytes both ways.
  @Test
  internal func aDialerReachesAListenerAndBothCarryFrames() async throws {
    let fromDialer = Data("to the holder".utf8)
    let fromListener = Data("to the requester".utf8)

    let heard = StreamRelayMailbox()
    let listener = StreamRelayListener { event in
      Task { await heard.record(event) }
    }
    listener.start(displayName: "ReFineID test \(UUID().uuidString.prefix(6))")
    defer { listener.cancel() }

    // A listener reports port zero until it is actually listening, and a
    // zero port is not an address a dialer can parse.
    var bound: UInt16?
    for _ in 0..<Self.attempts where bound == nil {
      let reported = listener.port
      if let reported, reported != 0 {
        bound = reported
      } else {
        try await Task.sleep(for: Self.pause)
      }
    }
    let port = try #require(bound, "the listener never bound a usable port")

    let dialed = StreamRelayMailbox()
    let dialer = StreamRelaySession(
      endpointLiterals: ["[::1]:\(port)", "127.0.0.1:\(port)"],
      preamble: fromDialer
    ) { event in
      Task { await dialed.record(event) }
    }
    dialer.start()
    defer { dialer.cancel() }

    let arrived = try? await Self.awaitFrame(in: heard)
    let listenerSaw = await heard.reported
    let dialerSaw = await dialed.reported
    let comment: Comment = """
      listener state: \(listener.state); \
      listener saw: \(listenerSaw); dialer saw: \(dialerSaw)
      """
    #expect(arrived == fromDialer, comment)

    try listener.send(fromListener)
    let answered = try? await Self.awaitFrame(in: dialed)
    let dialerFinally = await dialed.reported
    #expect(answered == fromListener, "dialer saw: \(dialerFinally)")
  }
}
