import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var selectedRange = "7d"
    @State private var trendsData: TrendsResp?
    @State private var isLoading = false
    
    let ranges = [
        ("7d", "Week"),
        ("30d", "Month"),
        ("90d", "3 Months")
    ]
    
    var body: some View {
        NavigationView {
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
                    .onChange(of: selectedRange) { _ in
                        Task { await loadTrends() }
                    }
                    
                    if isLoading {
                        ProgressView()
                            .padding()
                    } else {
                        // Weight Chart
                        if let weights = trendsData?.weight_series, !weights.isEmpty {
                            WeightChartView(data: weights)
                        }
                        
                        // Calorie Chart
                        if let caloriesIn = trendsData?.kcal_in_series,
                           let caloriesOut = trendsData?.kcal_out_series {
                            CalorieChartView(dataIn: caloriesIn, dataOut: caloriesOut)
                        }
                        
                        // Protein Chart
                        if let protein = trendsData?.protein_series {
                            ProteinChartView(data: protein)
                        }
                        
                        // Stats Summary
                        StatsSummaryView()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Trends")
            .task {
                await loadTrends()
            }
        }
    }
    
    private func loadTrends() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            trendsData = try await apiClient.getTrends(range: selectedRange)
        } catch {
            print("Failed to load trends: \(error)")
        }
    }
}

struct WeightChartView: View {
    let data: [[String: Any]]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Weight")
                .font(.headline)
                .padding(.horizontal)
            
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                    if let ts = point["ts"] as? String,
                       let kg = point["kg"] as? Double,
                       let date = ISO8601DateFormatter().date(from: ts) {
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Weight", kg)
                        )
                        .foregroundStyle(.blue)
                        
                        PointMark(
                            x: .value("Date", date),
                            y: .value("Weight", kg)
                        )
                        .foregroundStyle(.blue)
                    }
                }
            }
            .frame(height: 200)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            .padding(.horizontal)
        }
    }
}

struct CalorieChartView: View {
    let dataIn: [[String: Any]]
    let dataOut: [[String: Any]]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Calories")
                .font(.headline)
                .padding(.horizontal)
            
            Chart {
                ForEach(Array(dataIn.enumerated()), id: \.offset) { index, point in
                    if let dateStr = point["date"] as? String,
                       let kcal = point["kcal"] as? Int,
                       let date = dateFromString(dateStr) {
                        BarMark(
                            x: .value("Date", date),
                            y: .value("Calories", kcal)
                        )
                        .foregroundStyle(.green)
                        .position(by: .value("Type", "In"))
                    }
                }
                
                ForEach(Array(dataOut.enumerated()), id: \.offset) { index, point in
                    if let dateStr = point["date"] as? String,
                       let kcal = point["kcal"] as? Int,
                       let date = dateFromString(dateStr) {
                        BarMark(
                            x: .value("Date", date),
                            y: .value("Calories", kcal)
                        )
                        .foregroundStyle(.orange)
                        .position(by: .value("Type", "Out"))
                    }
                }
            }
            .frame(height: 200)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            .padding(.horizontal)
        }
    }
    
    private func dateFromString(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }
}

struct ProteinChartView: View {
    let data: [[String: Any]]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Protein")
                .font(.headline)
                .padding(.horizontal)
            
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                    if let dateStr = point["date"] as? String,
                       let g = point["g"] as? Double,
                       let date = dateFromString(dateStr) {
                        BarMark(
                            x: .value("Date", date),
                            y: .value("Protein", g)
                        )
                        .foregroundStyle(.blue)
                        
                        RuleMark(y: .value("Target", 100))
                            .foregroundStyle(.red.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
            }
            .frame(height: 200)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            .padding(.horizontal)
        }
    }
    
    private func dateFromString(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }
}

struct StatsSummaryView: View {
    @EnvironmentObject var store: DataStore
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                StatCard(
                    title: "Avg Daily",
                    value: "\(store.todayCaloriesIn)",
                    unit: "kcal",
                    color: .green
                )
                
                StatCard(
                    title: "Protein Avg",
                    value: String(format: "%.0f", store.todayProtein),
                    unit: "g",
                    color: .blue
                )
                
                if let weight = store.latestWeight {
                    StatCard(
                        title: "Current",
                        value: String(format: "%.1f", weight.weight_kg),
                        unit: "kg",
                        color: .purple
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(unit)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}