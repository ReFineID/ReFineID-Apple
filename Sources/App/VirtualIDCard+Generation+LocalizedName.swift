#if os(iOS)

  import CardCore

  internal extension VirtualIDCard.Generation {
    fileprivate var localizedName: String {
      VirtualIDCardOverlayLocalization.generationName(self)
    }
  }

#endif
