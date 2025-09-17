import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var selectedTab = 0
    @State private var selectedRange = "7d"
    @State private var trendsData: TrendsResp?
    @State private var isLoading = false
    @State private var errorMessage: String?

    let ranges = [
        ("3d", "3 Days"),
        ("7d", "Week"),
        ("30d", "Month"),
        ("90d", "3 Months"),
        ("all", "All Time")
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Selector
                Picker("Tab", selection: $selectedTab) {
                    Text("Charts").tag(0)
                    Text("Streaks").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if isLoading {
                    ProgressView("Loading trends...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if selectedTab == 0 {
                        // Charts Tab
                        ChartsTabView(
                            trendsData: trendsData,
                            selectedRange: $selectedRange,
                            ranges: ranges,
                            onRangeChange: { await loadTrends() }
                        )
                    } else {
                        // Streaks Tab
                        StreaksTabView(trendsData: trendsData)
                    }
                }
            }
            .navigationTitle("Trends")
            .refreshable {
                await loadTrends()
            }
            .task {
                await loadTrends()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadTrends() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await apiClient.getTrends(range: selectedRange)
            await MainActor.run {
                trendsData = data
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load trends: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

struct ChartsTabView: View {
    let trendsData: TrendsResp?
    @Binding var selectedRange: String
    let ranges: [(String, String)]
    let onRangeChange: () async -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Range Selector
                Picker("Range", selection: $selectedRange) {
                    ForEach(ranges, id: \.0) { range in
                        Text(range.1).tag(range.0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedRange) { _, _ in
                    Task { await onRangeChange() }
                }

                if let data = trendsData {
                    // Weight Chart
                    WeightChartView(weightPoints: data.weight_trend, range: selectedRange)

                    // Calorie Chart
                    CalorieChartView(caloriePoints: data.calorie_trend, range: selectedRange)

                    // Insights
                    if !data.insights.isEmpty {
                        InsightsCard(insights: data.insights)
                    }
                } else {
                    Text("No chart data available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.vertical)
        }
    }
}

struct StreaksTabView: View {
    let trendsData: TrendsResp?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let data = trendsData {
                    // Streaks Section
                    StreaksCard(streaks: data.current_streaks)

                    // Achievements
                    if !data.achievements.isEmpty {
                        AchievementsCard(achievements: data.achievements)
                    }
                } else {
                    Text("No streaks data available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.vertical)
        }
    }
}

struct StreaksCard: View {
    let streaks: [StreakInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Streaks 🔥")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(streaks, id: \.type) { streak in
                    StreakItemView(streak: streak)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct StreakItemView: View {
    let streak: StreakInfo

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: streak.icon)
                .font(.title2)
                .foregroundColor(.orange)

            Text("\(streak.current_streak)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(streak.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Best: \(streak.longest_streak)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct WeightChartView: View {
    let weightPoints: [WeightPoint]
    let range: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight Trend")
                .font(.headline)
                .padding(.horizontal)

            if weightPoints.isEmpty {
                Text("No weight data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(weightPoints, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.weight_kg)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.weight_kg)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }
                .frame(height: 200)
                .padding(.horizontal)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: weightPoints.count > 10 ? 7 : 1)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let weight = value.as(Double.self) {
                                Text("\(weight, specifier: "%.1f") kg")
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct CalorieChartView: View {
    let caloriePoints: [CaloriePoint]
    let range: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calories")
                .font(.headline)
                .padding(.horizontal)

            if caloriePoints.isEmpty {
                Text("No calorie data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(caloriePoints, id: \.date) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Calories", point.intake)
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .position(by: .value("Type", "Intake"))

                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Calories", point.burned)
                        )
                        .foregroundStyle(.orange.opacity(0.7))
                        .position(by: .value("Type", "Burned"))
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)
                .chartLegend(position: .bottom, alignment: .center) {
                    HStack(spacing: 20) {
                        Label("Intake", systemImage: "circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)

                        Label("Burned", systemImage: "circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: caloriePoints.count > 10 ? 7 : 1)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct AchievementsCard: View {
    let achievements: [Achievement]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Achievements 🏆")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 1), spacing: 8) {
                ForEach(achievements) { achievement in
                    HStack {
                        Text(achievement.title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        if achievement.progress >= 1.0 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            ProgressView(value: achievement.progress)
                                .frame(width: 50)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct InsightsCard: View {
    let insights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights 💡")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(insights, id: \.self) { insight in
                    HStack(alignment: .top) {
                        Text(insight)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

