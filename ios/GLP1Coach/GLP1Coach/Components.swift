import SwiftUI

// MARK: - App Background
struct AppBackground: View {
    var body: some View {
        LinearGradient.appGradient
            .ignoresSafeArea()
    }
}

// MARK: - Glass Card
struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Theme.spacing.lg)
            .background(
                (scheme == .dark ? Theme.cardBgDark : Theme.cardBgLight)
                    .blur(radius: 0.5)
            )
            .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Primary Button
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    let isLoading: Bool

    init(title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        }) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                Text(title)
                    .fontWeight(.semibold)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(LinearGradient.accentGradient)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
        .disabled(isLoading)
    }
}

// MARK: - Secondary Button
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    let isLoading: Bool

    init(title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        }) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                Text(title)
                    .fontWeight(.semibold)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.white.opacity(0.1))
        .foregroundStyle(Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous)
                .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
        )
        .disabled(isLoading)
    }
}

// MARK: - Pill Segment Picker
struct PillSegment: View {
    let items: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: Theme.spacing.sm) {
            ForEach(items.indices, id: \.self) { i in
                Text(items[i])
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(selection == i ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .onTapGesture {
                        withAnimation(Theme.springAnimation) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selection = i
                        }
                    }
            }
        }
    }
}

// MARK: - Progress Ring
struct ProgressRing: View {
    var progress: CGFloat // 0...1
    var label: String
    var value: String? = nil
    var size: CGFloat = 110

    /// Safe progress value that handles NaN and infinite values
    private var safeProgress: CGFloat {
        progress.isNaN || progress.isInfinite ? 0.0 : progress
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 12)

            Circle()
                .trim(from: 0, to: min(safeProgress, 1.0))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Theme.gradientTop, Theme.gradientBottom, Theme.accent]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.7), value: safeProgress)

            VStack(spacing: 4) {
                Text(value ?? "\(Int(safeProgress * 100))%")
                    .font(.title2.bold())
                Text(label)
                    .font(.caption)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Floating Tab Bar
struct FloatingTabBar: View {
    @Binding var selection: Int

    let items = [
        ("calendar", "Today"),
        ("plus.circle.fill", "Record"),
        ("message.fill", "Coach"),
        ("clock", "History"),
        ("chart.line.uptrend.xyaxis", "Trends"),
        ("person.fill", "Profile")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    withAnimation(Theme.springAnimation) {
                        selection = i
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: items[i].0)
                            .font(.system(size: i == selection ? 22 : 20, weight: .semibold))
                            .scaleEffect(i == selection ? 1.1 : 1.0)

                        if i == selection {
                            Text(items[i].1)
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(i == selection ? .white : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient.tabBarGradient,
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let showChevron: Bool

    init(_ title: String, showChevron: Bool = false) {
        self.title = title
        self.showChevron = showChevron
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Quick Action Button
struct QuickAction: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Insight Chip
struct InsightChip: View {
    let text: String
    let icon: String = "sparkles"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(text)
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .foregroundStyle(.white)
    }
}

// MARK: - Progress Dot
struct ProgressDot: View {
    let label: String
    let percentage: CGFloat
    let color: Color

    init(_ label: String, _ percentage: CGFloat, color: Color = .white) {
        self.label = label
        self.percentage = percentage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: 120, height: 8)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: max(8, 120 * percentage), height: 8)
                }
            Text(label)
                .foregroundStyle(.white)
                .font(.caption)
                .opacity(0.9)
        }
    }
}

// MARK: - Meal Row
struct MealRow: View {
    let title: String
    let kcal: Int
    let time: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text("\(kcal) kcal")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text(time)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Social Login Button
struct SocialButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating Camera Button
struct FloatingCameraButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Image(systemName: "camera.fill")
                .font(.title2)
                .padding(18)
                .background(LinearGradient.appGradient)
                .clipShape(Circle())
                .shadow(radius: 14, y: 8)
                .foregroundStyle(.white)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 88) // Above tab bar
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.6))

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Loading Skeleton
struct SkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .overlay(
                LinearGradient(
                    colors: [
                        .white.opacity(0.05),
                        .white.opacity(0.15),
                        .white.opacity(0.05)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: isAnimating ? 300 : -300)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}