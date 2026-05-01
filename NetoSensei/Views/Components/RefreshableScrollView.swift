//
//  RefreshableScrollView.swift
//  NetoSensei
//
//  A convenience wrapper around ScrollView with pull-to-refresh,
//  plus a reusable .onPullToRefresh() modifier.
//

import SwiftUI

// MARK: - Refreshable ScrollView

struct RefreshableScrollView<Content: View>: View {
    let content: Content
    let onRefresh: () async -> Void

    init(@ViewBuilder content: () -> Content, onRefresh: @escaping () async -> Void) {
        self.content = content()
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollView {
            content
        }
        .refreshable {
            await onRefresh()
        }
    }
}

// MARK: - Pull-to-Refresh Modifier

private struct RefreshableModifier: ViewModifier {
    let action: () async -> Void

    func body(content: Content) -> some View {
        content
            .refreshable {
                await action()
            }
    }
}

extension View {
    func onPullToRefresh(action: @escaping () async -> Void) -> some View {
        self.modifier(RefreshableModifier(action: action))
    }
}
