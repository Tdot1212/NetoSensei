//
//  InAppBrowserView.swift
//  NetoSensei
//
//  SFSafariViewController wrapper for in-app browsing of opt-out pages.
//

import SwiftUI
import SafariServices

struct InAppBrowserView: UIViewControllerRepresentable {
    let url: URL
    var tintColor: UIColor = .systemBlue

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = tintColor
        safari.dismissButtonStyle = .close
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
