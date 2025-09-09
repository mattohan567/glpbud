import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject var store: DataStore
    @State private var selectedRange = "7d"
    
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
                    
                    // Weight Chart
                    if !store.weights.isEmpty {
                        WeightChartView(weights: store.weights, range: selectedRange)
                    }
                    
                    // Calorie Chart
                    if !store.meals.isEmpty {
                        CalorieChartView(meals: store.meals, exercises: store.exercises, range: selectedRange)
                    }
                    
                    // Stats Summary
                    StatsCard(
                        totalMeals: store.meals.count,
                        totalExercises: store.exercises.count,
                        avgCalories: store.todayCaloriesIn
                    )
                }
                .padding(.vertical)
            }
            .navigationTitle("Trends")
        }
    }
}

struct WeightChartView: View {
    let weights: [Weight]
    let range: String
    
    private var filteredWeights: [Weight] {
        let days = Int(range.dropLast()) ?? 7
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return weights.filter { $0.timestamp > cutoff }.sorted { $0.timestamp < $1.timestamp }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight Trend")
                .font(.headline)
                .padding(.horizontal)
            
            if filteredWeights.isEmpty {
                Text("No weight data")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(filteredWeights) { weight in
                    LineMark(
                        x: .value("Date", weight.timestamp),
                        y: .value("Weight", weight.weight_kg)
                    )
                    .foregroundStyle(.blue)
                    
                    PointMark(
                        x: .value("Date", weight.timestamp),
                        y: .value("Weight", weight.weight_kg)
                    )
                    .foregroundStyle(.blue)
                }
                .frame(height: 200)
                .padding(.horizontal)
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
    let meals: [Meal]
    let exercises: [Exercise]
    let range: String
    
    private var dailyData: [(date: Date, intake: Int, burned: Int)] {
        let days = Int(range.dropLast()) ?? 7
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        var dataByDay: [Date: (intake: Int, burned: Int)] = [:]
        let calendar = Calendar.current
        
        for meal in meals.filter({ $0.timestamp > cutoff }) {
            let day = calendar.startOfDay(for: meal.timestamp)
            var dayData = dataByDay[day] ?? (0, 0)
            dayData.intake += meal.totals.kcal
            dataByDay[day] = dayData
        }
        
        for exercise in exercises.filter({ $0.timestamp > cutoff }) {
            let day = calendar.startOfDay(for: exercise.timestamp)
            var dayData = dataByDay[day] ?? (0, 0)
            dayData.burned += exercise.est_kcal ?? 0
            dataByDay[day] = dayData
        }
        
        return dataByDay.map { (date: $0.key, intake: $0.value.intake, burned: $0.value.burned) }
            .sorted { $0.date < $1.date }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calories")
                .font(.headline)
                .padding(.horizontal)
            
            if dailyData.isEmpty {
                Text("No calorie data")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(dailyData, id: \.date) { data in
                    BarMark(
                        x: .value("Date", data.date),
                        y: .value("Calories", data.intake)
                    )
                    .foregroundStyle(.green.opacity(0.7))
                    
                    BarMark(
                        x: .value("Date", data.date),
                        y: .value("Calories", data.burned)
                    )
                    .foregroundStyle(.orange.opacity(0.7))
                }
                .frame(height: 200)
                .padding(.horizontal)
                
                HStack(spacing: 20) {
                    Label("Intake", systemImage: "circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Label("Burned", systemImage: "circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct StatsCard: View {
    let totalMeals: Int
    let totalExercises: Int
    let avgCalories: Int
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                StatItem(label: "Meals", value: "\(totalMeals)")
                StatItem(label: "Workouts", value: "\(totalExercises)")
                StatItem(label: "Avg Calories", value: "\(avgCalories)")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct StatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}