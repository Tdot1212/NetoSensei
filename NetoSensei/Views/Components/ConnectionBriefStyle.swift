import SwiftUI

enum ConnectionBriefStyle {
    static let canvas = Color(
        light: Color(red: 0.95, green: 0.96, blue: 0.98),
        dark: Color(red: 0.05, green: 0.07, blue: 0.10)
    )
    static let surface = Color(
        light: .white,
        dark: Color(red: 0.09, green: 0.12, blue: 0.17)
    )
    static let rule = Color.primary.opacity(0.12)
    static let cautionInk = Color(
        light: Color(red: 0.50, green: 0.32, blue: 0.07),
        dark: Color(red: 1, green: 0.78, blue: 0.34)
    )
    static let mint = Color(red: 0.57, green: 0.96, blue: 0.82)
    static let softWhite = Color(red: 0.82, green: 0.89, blue: 0.96)
    static let hero = LinearGradient(
        colors: [Color(red: 0.09, green: 0.18, blue: 0.39), Color(red: 0.05, green: 0.23, blue: 0.26)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func connectionBriefColumn() -> some View {
        padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct BriefSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct BriefActionLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
