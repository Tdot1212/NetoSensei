//
//  AdaptiveLayout.swift
//  NetoSensei
//
//  iPad-optimized layout components that adapt between iPhone and iPad.
//  Provides adaptive containers, two-column layouts, adaptive grids,
//  and sidebar layouts based on horizontal size class.
//

import SwiftUI

// MARK: - Adaptive Container

struct AdaptiveContainer<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        GeometryReader { geometry in
            if isIPad && geometry.size.width > 700 {
                content
                    .frame(maxWidth: min(geometry.size.width - 100, 900))
                    .frame(maxWidth: .infinity)
            } else {
                content
            }
        }
    }
}

// MARK: - Two Column Layout (iPad)

struct TwoColumnLayout<Leading: View, Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let leading: Leading
    let trailing: Trailing
    let leadingWidth: CGFloat

    init(
        leadingWidth: CGFloat = 0.4,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leadingWidth = leadingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geometry in
            if horizontalSizeClass == .regular && geometry.size.width > 700 {
                HStack(spacing: 20) {
                    leading
                        .frame(width: geometry.size.width * leadingWidth)
                    trailing
                        .frame(maxWidth: .infinity)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        leading
                        trailing
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Adaptive Grid

struct AdaptiveGrid<Item: Identifiable, Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let items: [Item]
    let content: (Item) -> Content

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ]
        } else {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ]
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

// MARK: - iPad Sidebar Layout

struct iPadSidebarLayout<Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let sidebar: Sidebar
    let detail: Detail

    @State private var showSidebar = true

    init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                if showSidebar {
                    sidebar
                        .frame(width: 320)
                        .background(Color(UIColor.systemGray6))

                    Divider()
                }

                detail
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { withAnimation { showSidebar.toggle() } }) {
                        Image(systemName: "sidebar.left")
                    }
                }
            }
        } else {
            detail
        }
    }
}
