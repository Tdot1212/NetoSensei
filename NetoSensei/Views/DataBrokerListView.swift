//
//  DataBrokerListView.swift
//  NetoSensei
//
//  Full searchable list of all known data brokers.
//

import SwiftUI

struct DataBrokerListView: View {
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private let database = DataBrokerDatabase.shared

    var filteredBrokers: [DataBroker] {
        if searchText.isEmpty {
            return database.brokers
        }
        return database.searchBrokers(searchText)
    }

    var body: some View {
        NavigationView {
            List(filteredBrokers) { broker in
                NavigationLink(destination: DataBrokerDetailView(broker: broker)) {
                    FootprintBrokerRow(broker: broker)
                }
            }
            .searchable(text: $searchText, prompt: "Search brokers...")
            .navigationTitle("All Data Brokers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
