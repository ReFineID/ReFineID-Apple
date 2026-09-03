// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// Watches whether one named stream-transport service is on the network.
  ///
  /// A one-shot browser reports the first find and stops caring. A requester
  /// that has already published a borrowed identity has to know when that
  /// service leaves, so the identity can leave with it.
  public final class StreamRelayPresence: @unchecked Sendable {
    private let name: String
    private let onChange: @Sendable (Bool) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.stream-presence")
    private var browser: NWBrowser?
    private var isPresent = false
    private var hasDelivered = false

    /// Reports presence of the service published under `name`.
    ///
    /// The first empty browse is not an absence: the name service has not
    /// answered yet. Absence is delivered only after the service has been
    /// seen.
    @preconcurrency
    public init(
      matching name: String,
      onChange: @escaping @Sendable (Bool) -> Void
    ) {
      self.name = name
      self.onChange = onChange
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
        self?.apply(results)
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

    private func apply(_ results: Set<NWBrowser.Result>) {
      let found: Bool
      if name.isEmpty {
        found = !results.isEmpty
      } else {
        found = results.contains { result in
          guard case .service(let serviceName, _, _, _) = result.endpoint else {
            return false
          }
          return serviceName == name
        }
      }
      if !hasDelivered {
        hasDelivered = true
        isPresent = found
        if found {
          onChange(true)
        }
        return
      }
      guard found != isPresent else { return }
      isPresent = found
      onChange(found)
    }
  }
#endif
