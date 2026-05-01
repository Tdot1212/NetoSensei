//
//  AnimationConstants.swift
//  NetoSensei
//
//  Animation constants and utilities for consistent UX
//

import SwiftUI

struct AnimationConstants {
    // MARK: - Duration

    static let fast: Double = 0.2
    static let standard: Double = 0.3
    static let slow: Double = 0.5
    static let verySlow: Double = 0.8

    // MARK: - Spring Animations

    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let springSmooth = Animation.spring(response: 0.5, dampingFraction: 0.8)

    // MARK: - Easing Animations

    static let easeInOut = Animation.easeInOut(duration: standard)
    static let easeIn = Animation.easeIn(duration: standard)
    static let easeOut = Animation.easeOut(duration: standard)
    static let linear = Animation.linear(duration: standard)

    // MARK: - Card Animations

    static let cardAppear = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let cardDismiss = Animation.easeOut(duration: fast)

    // MARK: - Sheet Animations

    static let sheetPresent = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let sheetDismiss = Animation.easeOut(duration: 0.25)

    // MARK: - Progress Animations

    static let progressUpdate = Animation.linear(duration: 0.1)
    static let progressComplete = Animation.spring(response: 0.5, dampingFraction: 0.7)

    // MARK: - Transition Delays

    static let staggerDelay: Double = 0.05
    static let cardDelay: Double = 0.1
}

// MARK: - View Extensions for Animations

extension View {
    /// Fade in with optional delay
    func fadeIn(delay: Double = 0) -> some View {
        self
            .opacity(0)
            .animation(
                AnimationConstants.easeInOut.delay(delay),
                value: UUID()
            )
            .onAppear {
                withAnimation(AnimationConstants.easeInOut.delay(delay)) {}
            }
    }

    /// Slide in from bottom
    func slideInFromBottom(delay: Double = 0) -> some View {
        self.modifier(SlideInModifier(edge: .bottom, delay: delay))
    }

    /// Slide in from top
    func slideInFromTop(delay: Double = 0) -> some View {
        self.modifier(SlideInModifier(edge: .top, delay: delay))
    }

    /// Slide in from leading
    func slideInFromLeading(delay: Double = 0) -> some View {
        self.modifier(SlideInModifier(edge: .leading, delay: delay))
    }

    /// Scale in animation
    func scaleIn(delay: Double = 0) -> some View {
        self.modifier(ScaleInModifier(delay: delay))
    }

    /// Bounce in animation
    func bounceIn(delay: Double = 0) -> some View {
        self.modifier(BounceInModifier(delay: delay))
    }

    /// Shimmer loading effect
    func shimmer(isLoading: Bool) -> some View {
        self.modifier(ShimmerModifier(isLoading: isLoading))
    }

    /// Pulse animation (for progress indicators)
    func pulse(isActive: Bool) -> some View {
        self.modifier(PulseModifier(isActive: isActive))
    }
}

// MARK: - Animation Modifiers

struct SlideInModifier: ViewModifier {
    let edge: Edge
    let delay: Double

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .offset(
                x: !isVisible && edge == .leading ? -20 : 0,
                y: !isVisible && edge == .top ? -20 :
                   !isVisible && edge == .bottom ? 20 : 0
            )
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(AnimationConstants.spring.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

struct ScaleInModifier: ViewModifier {
    let delay: Double

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.8)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(AnimationConstants.spring.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

struct BounceInModifier: ViewModifier {
    let delay: Double

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.5)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(AnimationConstants.springBouncy.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

struct ShimmerModifier: ViewModifier {
    let isLoading: Bool

    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if isLoading {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                .white.opacity(0.3),
                                .clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: phase * geometry.size.width * 2 - geometry.size.width)
                        .onAppear {
                            withAnimation(
                                Animation.linear(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                            ) {
                                phase = 1
                            }
                        }
                    }
                }
            )
            .clipped()
    }
}

struct PulseModifier: ViewModifier {
    let isActive: Bool

    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isActive) { oldValue, newValue in
                if newValue {
                    withAnimation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                    ) {
                        scale = 1.05
                    }
                } else {
                    withAnimation {
                        scale = 1.0
                    }
                }
            }
    }
}

// MARK: - Staggered Animation Helper

struct StaggeredAppearance<Content: View>: View {
    let items: Int
    let content: (Int) -> Content

    var body: some View {
        ForEach(0..<items, id: \.self) { index in
            content(index)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .animation(
                    AnimationConstants.spring.delay(Double(index) * AnimationConstants.staggerDelay),
                    value: index
                )
        }
    }
}
