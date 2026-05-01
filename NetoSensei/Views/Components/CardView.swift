//
//  CardView.swift
//  NetoSensei
//
//  Reusable card component for consistent UI
//  STEP 5 - Global UI Components
//

import SwiftUI

/// Standard card component with consistent styling
struct CardView<Content: View>: View {
    var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacingM) {
            content()
        }
        .padding()
        .background(AppColors.card)
        .cornerRadius(UIConstants.cornerRadiusL)
        .shadow(radius: UIConstants.cardShadowRadius, y: 2)
    }
}

// MARK: - Preview

struct CardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            CardView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample Card")
                        .font(.headline)
                    Text("This is a sample card with some content")
                        .font(.body)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding()
        }
        .background(AppColors.background)
    }
}
