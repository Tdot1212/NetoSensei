//
//  StatusDot.swift
//  NetoSensei
//
//  Status indicator dot component
//  STEP 5 - Global UI Components
//

import SwiftUI

/// A colored dot indicating status (green/yellow/red)
struct StatusDot: View {
    var color: Color
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.5), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Preview

struct StatusDot_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            StatusDot(color: AppColors.green)
            StatusDot(color: AppColors.yellow)
            StatusDot(color: AppColors.red)
        }
        .padding()
    }
}
