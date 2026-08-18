#if os(iOS)

  import CardCore

  extension VirtualIDCard.FaultPreset {
    internal var localizedName: String {
      VirtualIDCardOverlayLocalization.faultPresetName(self)
    }
  }

#endif
