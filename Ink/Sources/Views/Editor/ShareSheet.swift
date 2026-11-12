import SwiftUI
import UIKit

/// UIActivityViewController 래퍼.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// true면 AirDrop만 남기고 다른 공유 대상을 제외한다.
    var airDropOnly = false

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if airDropOnly {
            controller.excludedActivityTypes = [
                .postToFacebook, .postToTwitter, .postToWeibo, .message, .mail, .print, .copyToPasteboard,
                .assignToContact, .saveToCameraRoll, .addToReadingList, .postToFlickr, .postToVimeo,
                .postToTencentWeibo, .openInIBooks, .markupAsPDF, .sharePlay, .collaborationInviteWithLink,
                .collaborationCopyLink, .addToHomeScreen,
            ]
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
