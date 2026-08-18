#if os(iOS)

  import CardCore

  extension VirtualIDCard.CertificateState {
    internal var localizedName: String {
      VirtualIDCardOverlayLocalization.certificateStateName(self)
    }
  }

#endif
