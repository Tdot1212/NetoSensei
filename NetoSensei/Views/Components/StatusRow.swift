//
//  StatusRow.swift
//  NetoSensei
//
//  Status row component with title, value, and colored indicator
//  STEP 5 - Global UI Components
//

import SwiftUI

/// A row showing a status with title, value, and colored dot
struct StatusRow: View {
    var title: String
    var value: String
    var color: Color
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: UIConstants.spacingM) {
            // Icon (optional)
            if let iconName = icon {
                Image(systemName: iconName)
                    .font(.system(size: UIConstants.iconSizeM))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: UIConstants.iconSizeM)
            }

            // Title
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            // Value
            Text(value)
                .font(.body.bold())
                .foregroundColor(AppColors.textPrimary)

            // Status dot
            StatusDot(color: color)
        }
    }
}

// MARK: - Preview

struct StatusRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            StatusRow(title: "Wi-Fi", value: "Connected", color: AppColors.green, icon: "wifi")
            StatusRow(title: "Router", value: "Reachable", color: AppColors.green, icon: "antenna.radiowaves.left.and.right")
            StatusRow(title: "DNS", value: "Slow", color: AppColors.yellow, icon: "server.rack")
            StatusRow(title: "VPN", value: "Inactive", color: AppColors.red, icon: "lock.shield")
        }
        .padding()
    }
}
