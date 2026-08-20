// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// Finds a card holder publishing the stream transport.
  ///
  /// This browses with the plain name service rather than the nearby
  /// framework. Both are fed by the same records, but only one of them
  /// hands the result to the app on a device whose system generation
  /// differs from its peer's.
  public final class StreamRelayBrowser: @unchecked Sendable {
    private let onFound: @Sendable (NWEndpoint) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.stream-browser")
    private var browser: NWBrowser?
    private var reported = false

    /// Reports the first published holder to one owner.
    @preconcurrency
    public init(onFound: @escaping @Sendable (NWEndpoint) -> Void) {
      self.onFound = onFound
    }

    /// Starts browsing.
    public func start() {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      let made = NWBrowser(
        for: .bonjour(type: StreamRelayListener.serviceType, domain: nil),
        using: parameters
      )
      made.browseResultsChangedHandler = { [weak self] results, _ in
        guard let self, let first = results.first else { return }
        queue.async { [weak self] in
          guard let self, !reported else { return }
          reported = true
          onFound(first.endpoint)
        }
      }
      browser = made
      made.start(queue: queue)
    }

    /// Stops browsing.
    public func cancel() {
      queue.async {
        self.browser?.cancel()
        self.browser = nil
      }
    }
  }
#endif
