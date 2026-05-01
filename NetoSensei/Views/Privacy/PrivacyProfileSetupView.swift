//
//  PrivacyProfileSetupView.swift
//  NetoSensei
//
//  Form for setting up the user's privacy profile (name, email, location)
//  used to generate GDPR/CCPA removal request emails.
//

import SwiftUI

struct PrivacyProfileSetupView: View {
    @StateObject private var manager = PrivacyActionCenterManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var state = ""
    @State private var country = "United States"

    let countries = ["United States", "United Kingdom", "Canada", "Australia", "Germany", "France", "China", "Hong Kong", "Japan", "Other"]

    var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Required")) {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                }

                Section(header: Text("Optional — improves email accuracy")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)

                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)

                    Picker("Country", selection: $country) {
                        ForEach(countries, id: \.self) { Text($0).tag($0) }
                    }

                    TextField("City", text: $city)
                    TextField("State / Province", text: $state)
                }

                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text("Stored on your device only. Used to generate removal request emails. Never uploaded anywhere.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Privacy Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(!isValid)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        if let p = manager.profile {
            firstName = p.firstName
            lastName = p.lastName
            email = p.email ?? ""
            phone = p.phone ?? ""
            city = p.city ?? ""
            state = p.state ?? ""
            country = p.country
        }
    }

    private func save() {
        let profile = PrivacyProfile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            country: country
        )
        manager.saveProfile(profile)
        dismiss()
    }
}
