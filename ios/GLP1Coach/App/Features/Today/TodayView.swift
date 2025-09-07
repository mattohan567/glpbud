import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Calorie Summary Card
                    CalorieSummaryCard()
                    
                    // Macro Distribution
                    MacroDistributionCard()
                    
                    // Next Medication
                    if let nextDose = store.todayStats?.next_dose_ts {
                        MedicationReminderCard(nextDose: nextDose)
                    }
                    
                    // Recent Logs
                    RecentLogsSection()
                }
                .padding()
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .refreshable {
                await refreshDataAsync()
            }
        }
        .task {
            await refreshDataAsync()
        }
    }
    
    private func refreshData() {
        Task {
            await refreshDataAsync()
        }
    }
    
    private func refreshDataAsync() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let todayResp = try await apiClient.getToday()
            await MainActor.run {
                store.todayStats = todayResp
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CalorieSummaryCard: View {
    @EnvironmentObject var store: DataStore
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Calorie Balance")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 30) {
                VStack {
                    Text("\(store.todayCaloriesIn)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("In")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "minus")
                    .foregroundColor(.secondary)
                
                VStack {
                    Text("\(store.todayCaloriesOut)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Out")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "equal")
                    .foregroundColor(.secondary)
                
                VStack {
                    Text("\(store.todayCaloriesIn - store.todayCaloriesOut)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(netCaloriesColor)
                    Text("Net")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var netCaloriesColor: Color {
        let net = store.todayCaloriesIn - store.todayCaloriesOut
        if net < 1200 {
            return .orange
        } else if net > 2000 {
            return .red
        } else {
            return .green
        }
    }
}

struct MacroDistributionCard: View {
    @EnvironmentObject var store: DataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macros")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                MacroRow(
                    name: "Protein",
                    value: store.todayProtein,
                    unit: "g",
                    target: 100,
                    color: .blue
                )
                
                MacroRow(
                    name: "Carbs",
                    value: store.todayStats?.carbs_g ?? 0,
                    unit: "g",
                    target: 150,
                    color: .orange
                )
                
                MacroRow(
                    name: "Fat",
                    value: store.todayStats?.fat_g ?? 0,
                    unit: "g",
                    target: 50,
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct MacroRow: View {
    let name: String
    let value: Double
    let unit: String
    let target: Double
    let color: Color
    
    var progress: Double {
        min(value / target, 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value))\(unit) / \(Int(target))\(unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}

struct MedicationReminderCard: View {
    let nextDose: String
    
    var formattedTime: String {
        guard let date = ISO8601DateFormatter().date(from: nextDose) else {
            return "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            Image(systemName: "pills.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text("Next Dose")
                    .font(.headline)
                Text(formattedTime)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Log") {
                // Navigate to med logging
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct RecentLogsSection: View {
    @EnvironmentObject var store: DataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Logs")
                .font(.headline)
                .foregroundColor(.secondary)
            
            ForEach(store.todayMeals.prefix(3)) { meal in
                HStack {
                    Image(systemName: "fork.knife")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading) {
                        Text(meal.items.first?.name ?? "Meal")
                            .font(.subheadline)
                        Text("\(meal.totals.kcal) kcal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(meal.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if meal.syncStatus == .pending {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}