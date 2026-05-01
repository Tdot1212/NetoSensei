//
//  AllActionsView.swift
//  NetoSensei
//
//  Filtered list of all opt-out actions, sortable by status and difficulty.
//

import SwiftUI

struct AllActionsView: View {
    @StateObject private var manager = PrivacyActionCenterManager.shared

    var filter: OptOutAction.Difficulty?
    var filterCategory: OptOutAction.BrokerCategory?

    init(filter: OptOutAction.Difficulty? = nil, filterCategory: OptOutAction.BrokerCategory? = nil) {
        self.filter = filter
        self.filterCategory = filterCategory
    }

    var filteredActions: [OptOutAction] {
        var actions = manager.optOutActions

        if let diff = filter {
            actions = actions.filter { $0.difficulty == diff }
        }

        if let cat = filterCategory {
            actions = actions.filter { $0.category == cat }
        }

        return actions.sorted { a, b in
            if a.status.sortOrder != b.status.sortOrder {
                return a.status.sortOrder < b.status.sortOrder
            }
            return a.difficulty.sortOrder < b.difficulty.sortOrder
        }
    }

    var title: String {
        if let diff = filter {
            return "\(diff.rawValue) Opt-Outs"
        }
        if let cat = filterCategory {
            return cat.rawValue
        }
        return "All Opt-Outs"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(filteredActions) { action in
                    NavigationLink(destination: OptOutActionDetailView(actionID: action.id)) {
                        OptOutActionRow(action: action)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
