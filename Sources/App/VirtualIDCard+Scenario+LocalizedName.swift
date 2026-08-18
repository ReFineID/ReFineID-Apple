#if os(iOS)

  import CardCore

  extension VirtualIDCard.Scenario {
    internal var localizedName: String {
      VirtualIDCardOverlayLocalization.scenarioName(self)
    }
  }

#endif
