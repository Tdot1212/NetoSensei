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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(ConnectionBriefStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(ConnectionBriefStyle.rule, lineWidth: 1)
                .allowsHitTesting(false)
        }
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
