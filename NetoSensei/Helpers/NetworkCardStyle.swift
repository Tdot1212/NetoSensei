//
//  NetworkCardStyle.swift
//  NetoSensei
//
//  Reusable card modifier for consistent styling across the app
//

import SwiftUI

// MARK: - Network Card Style

struct NetworkCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - View Extension

extension View {
    /// Apply consistent card styling used throughout the app
    func networkCard() -> some View {
        modifier(NetworkCardStyle())
    }

    /// Apply card styling with custom padding
    func networkCard(padding: CGFloat) -> some View {
        modifier(NetworkCardStyle(padding: padding))
    }

    /// Apply card styling with custom corner radius
    func networkCard(cornerRadius: CGFloat) -> some View {
        modifier(NetworkCardStyle(cornerRadius: cornerRadius))
    }

    /// Apply card styling with custom padding and corner radius
    func networkCard(padding: CGFloat, cornerRadius: CGFloat) -> some View {
        modifier(NetworkCardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Section Header Style

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

extension View {
    func sectionHeader() -> some View {
        modifier(SectionHeaderStyle())
    }
}

// MARK: - Metric Display Style

struct MetricValueStyle: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.title2.bold())
            .foregroundColor(color)
    }
}

struct MetricLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

extension View {
    func metricValue(color: Color = .primary) -> some View {
        modifier(MetricValueStyle(color: color))
    }

    func metricLabel() -> some View {
        modifier(MetricLabelStyle())
    }
}
