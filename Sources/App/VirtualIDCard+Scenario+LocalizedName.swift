#if os(iOS)

  import CardCore

  internal extension VirtualIDCard.Scenario {
    fileprivate var localizedName: String {
      VirtualIDCardOverlayLocalization.scenarioName(self)
    }
  }

#endif
