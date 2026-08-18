#if os(iOS)

  import Foundation

  internal extension Notification.Name {
    static let virtualIDCardEditorDidDismiss = Notification.Name(
      "fi.refineid.virtual-id-card-editor-did-dismiss")
  }

#endif
