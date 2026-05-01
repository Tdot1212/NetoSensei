//
//  ProfileSetupView.swift
//  NetoSensei
//
//  Profile setup form for the Digital Footprint Scanner.
//  Collects user info for searching data broker sites.
//

import SwiftUI

struct ProfileSetupView: View {
    @StateObject private var scanner = DigitalFootprintScanner.shared
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var middleName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var state = ""
    @State private var country = "United States"

    let countries = ["United States", "United Kingdom", "Canada", "Australia", "Germany", "France", "Japan", "Other"]
    let usStates = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
                    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
                    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
                    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
                    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"]

    var isValid: Bool {
        !firstName.isEmpty && !lastName.isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Required Information")) {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("Middle Name (optional)", text: $middleName)
                }

                Section(header: Text("Contact Information"), footer: Text("Used to search for your profiles and for removal requests.")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)

                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section(header: Text("Location"), footer: Text("Helps narrow down search results.")) {
                    Picker("Country", selection: $country) {
                        ForEach(countries, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }

                    TextField("City", text: $city)

                    if country == "United States" {
                        Picker("State", selection: $state) {
                            Text("Select State").tag("")
                            ForEach(usStates, id: \.self) { s in
                                Text(s).tag(s)
                            }
                        }
                    } else {
                        TextField("State/Province", text: $state)
                    }
                }

                Section(header: Text("Privacy Note")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.green)
                            Text("Your information is stored locally on your device and is only used to search data broker sites.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "icloud.slash")
                                .foregroundColor(.blue)
                            Text("We never upload your data to any server.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Your Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveProfile() }
                        .disabled(!isValid)
                        .bold()
                }
            }
            .onAppear {
                loadExistingProfile()
            }
        }
    }

    private func loadExistingProfile() {
        if let profile = scanner.scanProfile {
            firstName = profile.firstName
            lastName = profile.lastName
            middleName = profile.middleName ?? ""
            email = profile.email ?? ""
            phone = profile.phone ?? ""
            city = profile.city ?? ""
            state = profile.state ?? ""
            country = profile.country
        }
    }

    private func saveProfile() {
        let profile = ScanProfile(
            firstName: firstName,
            lastName: lastName,
            middleName: middleName.isEmpty ? nil : middleName,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            country: country
        )

        scanner.scanProfile = profile
        dismiss()
    }
}
