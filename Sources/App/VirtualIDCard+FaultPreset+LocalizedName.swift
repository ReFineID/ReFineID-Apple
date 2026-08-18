#if os(iOS)

  import CardCore

  extension VirtualIDCard.FaultPreset {
    fileprivate var localizedName: String {
      VirtualIDCardOverlayLocalization.faultPresetName(self)
    }
  }

#endif
