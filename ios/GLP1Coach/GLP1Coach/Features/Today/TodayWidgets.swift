import SwiftUI
import Charts

// MARK: - Enhanced Progress Widgets

struct MacroProgressCard: View {
    let title: String
    let current: Double
    let target: Double
    let unit: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(Int(current))/\(Int(target))\(unit)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)

                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * min(progress, 1.0), height: 6)
                        .cornerRadius(3)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)

            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundStyle(progress > 1.0 ? Theme.warn : color)
        }
        .padding(12)
        .frame(minHeight: 110)
        .background(Theme.cardBackground)
        .cornerRadius(12)
    }
}

struct CalorieProgressRing: View {
    let netCalories: Int
    let target: Int
    let progress: Double

    private var progressColor: Color {
        switch progress {
        case 0..<0.8: return Theme.accent
        case 0.8..<1.1: return Theme.success
        default: return Theme.warn
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Theme.cardBackground, lineWidth: 12)
                    .frame(width: 100, height: 100)

                // Progress ring
                Circle()
                    .trim(from: 0, to: min(progress, 1.5)) // Allow overrun visualization
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: progress)

                // Center content
                VStack(spacing: 2) {
                    Text("\(netCalories)")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("NET")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Text("Goal: \(target)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// ActivityTimelineCard and TimelineRow removed - using simplified approach in TodayView

struct SparklineChart: View {
    let data: DailySparkline
    let height: CGFloat = 60

    private var chartData: [SparklinePoint] {
        data.calories.enumerated().map { index, calories in
            SparklinePoint(
                day: data.dates[safe: index] ?? "",
                calories: calories,
                weight: data.weights[safe: index] ?? nil
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("7-Day Trend")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Net Calories")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }

            Chart(chartData) { point in
                LineMark(
                    x: .value("Day", point.dayIndex),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                AreaMark(
                    x: .value("Day", point.dayIndex),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(Theme.accent.opacity(0.1))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: height)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(12)
    }
}

struct SparklinePoint: Identifiable {
    let id = UUID()
    let day: String
    let calories: Int
    let weight: Double?

    var dayIndex: Int {
        // Simple index for x-axis positioning
        return Int(day.suffix(2)) ?? 0
    }
}

struct NextActionsCard: View {
    let actions: [NextAction]
    let onActionTap: (NextAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Suggested Actions")

            if actions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.success)
                    Text("All caught up!")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(actions.prefix(3).enumerated()), id: \.element.title) { index, action in
                        NextActionRow(action: action) {
                            onActionTap(action)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minHeight: 120)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
}

struct NextActionRow: View {
    let action: NextAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)

                    if let subtitle = action.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct InsightCard: View {
    let tip: String
    let streakDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if streakDays > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(Theme.warn)
                        Text("\(streakDays)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.warn.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer()

                Text("Daily Insight")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(tip)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.05), Theme.accent.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.accent.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

struct WeightTrendCard: View {
    let currentWeight: Double?
    let trend7d: Double?
    let unit: String
    var isLoading: Bool = false

    private var trendIcon: String {
        guard let trend = trend7d else { return "minus" }
        return trend > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private var trendColor: Color {
        guard let trend = trend7d else { return Theme.textSecondary }
        return trend > 0 ? Color(hex: 0xFEF08A) : Theme.success // Light yellow for better visibility
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Weight")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                if isLoading {
                    // Show loading placeholder
                    HStack {
                        Text("---")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.textSecondary.opacity(0.3))
                    }
                } else if let weight = currentWeight {
                    Text(WeightUtils.displayWeight(weight, unit: unit))
                        .font(.title2.bold())
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Text("Log weight →")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            if let trend = trend7d {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: trendIcon)
                            .font(.caption)
                        Text("\(abs(WeightUtils.convertFromKg(trend, toUnit: unit)), specifier: "%.1f") \(unit)")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(trendColor)

                    Text("7 days")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(minHeight: 120)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
}

// MARK: - Helper Extensions

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}