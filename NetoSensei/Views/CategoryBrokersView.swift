//
//  CategoryBrokersView.swift
//  NetoSensei
//
//  Lists data brokers filtered by category with navigation to detail views.
//

import SwiftUI

struct CategoryBrokersView: View {
    let category: DataBroker.Category

    var brokers: [DataBroker] {
        DataBrokerDatabase.shared.getBrokersByCategory(category)
    }

    var body: some View {
        List(brokers) { broker in
            NavigationLink(destination: DataBrokerDetailView(broker: broker)) {
                FootprintBrokerRow(broker: broker)
            }
        }
        .navigationTitle(category.rawValue)
    }
}

struct FootprintBrokerRow: View {
    let broker: DataBroker

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: broker.category.icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(broker.name)
                    .font(.subheadline.bold())
                Text(broker.difficulty.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(broker.optOutMethod.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
