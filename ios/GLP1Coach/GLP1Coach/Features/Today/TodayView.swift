import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Calorie Summary Card
                    CalorieSummaryCard(
                        caloriesIn: store.todayCaloriesIn,
                        caloriesOut: store.todayCaloriesOut,
                        target: Config.defaultCalorieTarget
                    )
                    
                    // Macros Card
                    MacrosCard(
                        protein: store.todayProtein,
                        carbs: store.todayCarbs,
                        fat: store.todayFat
                    )
                    
                    // Recent Meals
                    if !store.todayMeals.isEmpty {
                        RecentMealsCard(meals: store.todayMeals)
                    }
                    
                    // Weight Card
                    if let weightKg = store.latestWeight {
                        LatestWeightCard(weightKg: weightKg)
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .refreshable {
                await loadTodayStats()
            }
            .task {
                await loadTodayStats()
            }
            .onAppear {
                Task {
                    await loadTodayStats()
                }
            }
        }
    }
    
    private func loadTodayStats() async {
        await store.refreshTodayStats(apiClient: apiClient)
    }
}

struct CalorieSummaryCard: View {
    let caloriesIn: Int
    let caloriesOut: Int
    let target: Int
    
    var net: Int { caloriesIn - caloriesOut }
    var remaining: Int { target - net }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Calorie Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                VStack {
                    Text("\(caloriesIn)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Intake")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "minus")
                    .foregroundColor(.secondary)
                
                VStack {
                    Text("\(caloriesOut)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Burned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "equal")
                    .foregroundColor(.secondary)
                
                VStack {
                    Text("\(net)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(net > target ? .red : .green)
                    Text("Net")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ProgressView(value: max(0, Double(net)), total: Double(max(1, target)))
                .tint(net > target ? .red : .blue)
            
            Text("\(abs(remaining)) kcal \(remaining > 0 ? "remaining" : "over")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct MacrosCard: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Macros")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                MacroItem(name: "Protein", value: protein, unit: "g", color: .blue)
                MacroItem(name: "Carbs", value: carbs, unit: "g", color: .orange)
                MacroItem(name: "Fat", value: fat, unit: "g", color: .green)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct MacroItem: View {
    let name: String
    let value: Double
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f", value))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecentMealsCard: View {
    let meals: [Meal]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Recent Meals")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(meals.prefix(3)) { meal in
                HStack {
                    VStack(alignment: .leading) {
                        Text(meal.timestamp, style: .time)
                            .font(.subheadline)
                        Text("\(meal.totals.kcal) kcal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: meal.source == .image ? "camera" : "text.alignleft")
                        .foregroundColor(.secondary)
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

struct WeightCard: View {
    let weight: Weight
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Latest Weight")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f kg", weight.weight_kg))
                    .font(.title3)
                    .fontWeight(.bold)
            }
            Spacer()
            Text(weight.timestamp, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct LatestWeightCard: View {
    let weightKg: Double
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Latest Weight")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f kg", weightKg))
                    .font(.title3)
                    .fontWeight(.bold)
            }
            Spacer()
            Text("From API")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}