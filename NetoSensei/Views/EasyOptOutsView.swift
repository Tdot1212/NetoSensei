//
//  EasyOptOutsView.swift
//  NetoSensei
//
//  Lists data brokers with easy opt-out difficulty for quick removal.
//

import SwiftUI

struct EasyOptOutsView: View {
    var easyBrokers: [DataBroker] {
        DataBrokerDatabase.shared.getEasyOptOuts()
    }

    var body: some View {
        List(easyBrokers) { broker in
            NavigationLink(destination: DataBrokerDetailView(broker: broker)) {
                FootprintBrokerRow(broker: broker)
            }
        }
        .navigationTitle("Easy Opt-Outs")
    }
}
