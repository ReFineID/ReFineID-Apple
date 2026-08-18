#if os(iOS)

  import CardCore

  extension VirtualIDCard.Scenario {
    fileprivate var localizedName: String {
      VirtualIDCardOverlayLocalization.scenarioName(self)
    }
  }

#endif
