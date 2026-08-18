#if os(iOS)

  import CardCore

  extension VirtualIDCard.CertificateState {
    fileprivate var localizedName: String {
      VirtualIDCardOverlayLocalization.certificateStateName(self)
    }
  }

#endif
