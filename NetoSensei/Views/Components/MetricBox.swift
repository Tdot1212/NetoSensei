//
//  MetricBox.swift
//  NetoSensei
//
//  Metric display box component (for ping, jitter, etc.)
//  STEP 5 - Global UI Components
//

import SwiftUI

/// A box displaying a metric with title and value
struct MetricBox: View {
    var title: String
    var value: String
    var unit: String = ""
    var color: Color = AppColors.textPrimary
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacingS) {
            // Title with optional icon
            HStack(spacing: UIConstants.spacingXS) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.system(size: UIConstants.iconSizeS))
                        .foregroundColor(AppColors.textSecondary)
                }
                Text(title)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            // Value
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundColor(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColors.card)
        .cornerRadius(UIConstants.cornerRadiusM)
    }
}

// MARK: - Preview

struct MetricBox_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            MetricBox(title: "Ping", value: "23", unit: "ms", color: AppColors.green, icon: "timer")
            MetricBox(title: "Jitter", value: "5", unit: "ms", color: AppColors.green, icon: "waveform.path.ecg")
        }
        .padding()
    }
}
