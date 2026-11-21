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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var title: String
    var value: String
    var color: Color
    var icon: String? = nil

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                HStack {
                    valueLabel
                    StatusDot(color: color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: UIConstants.spacingM) {
                titleLabel
                Spacer()
                valueLabel
                StatusDot(color: color)
            }
        }
    }

    private var titleLabel: some View {
        HStack(spacing: UIConstants.spacingM) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: UIConstants.iconSizeM))
                    .frame(width: UIConstants.iconSizeM)
            }
            Text(title)
                .font(.subheadline)
        }
        .foregroundStyle(AppColors.textSecondary)
    }

    private var valueLabel: some View {
        Text(value)
            .font(.body.bold())
            .foregroundStyle(AppColors.textPrimary)
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
