//
//  LoadingOverlay.swift
//  NetoSensei
//
//  Loading overlay with spinner for long-running tests
//  STEP 5 - Global UI Components
//

import SwiftUI

/// A translucent overlay with loading spinner
struct LoadingOverlay: View {
    var message: String = "Loading..."
    var progress: Double? = nil

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Loading card
            VStack(spacing: UIConstants.spacingL) {
                // Progress indicator
                if let progressValue = progress {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(AppColors.accent)
                        .frame(width: 200)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                }

                // Message
                Text(message)
                    .font(.body)
                    .foregroundColor(.white)
            }
            .padding(UIConstants.spacingXL)
            .background(AppColors.card)
            .cornerRadius(UIConstants.cornerRadiusL)
            .shadow(radius: UIConstants.cardShadowRadius)
        }
    }
}

// MARK: - Preview

struct LoadingOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Sample background content
            VStack {
                Text("Main Content")
                    .font(.largeTitle)
            }

            // Overlay
            LoadingOverlay(message: "Running diagnostic...", progress: 0.5)
        }
    }
}
