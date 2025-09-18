import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var isLoading = false
    @State private var quickActionSelection = 1

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.spacing.lg) {
                    // Hero Title
                    Text("Today")
                        .font(.heroTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 8)

                    // Calorie & Macros Progress
                    GlassCard {
                        HStack(spacing: 18) {
                            ProgressRing(
                                progress: CGFloat(store.todayCaloriesIn - store.todayCaloriesOut) / CGFloat(max(1, Config.defaultCalorieTarget)),
                                label: "Calories",
                                value: "\(store.todayCaloriesIn - store.todayCaloriesOut)"
                            )

                            VStack(spacing: 12) {
                                ProgressDot("Protein", CGFloat(store.todayProtein) / 120, color: Theme.gradientTop)
                                ProgressDot("Carbs", CGFloat(store.todayCarbs) / 150, color: Theme.warn)
                                ProgressDot("Fat", CGFloat(store.todayFat) / 50, color: Theme.accent)
                            }
                        }
                    }

                    // Quick Actions
                    GlassCard {
                        VStack(spacing: Theme.spacing.md) {
                            SectionHeader("Quick Actions")

                            HStack(spacing: 12) {
                                QuickAction(title: "Log Meal", icon: "fork.knife") {
                                    // Navigation to Record tab will be handled in MainTabView
                                }
                                QuickAction(title: "Log Weight", icon: "scalemass") {
                                    // Navigation to Record tab
                                }
                                QuickAction(title: "Exercise", icon: "figure.run") {
                                    // Navigation to Record tab
                                }
                            }
                        }
                    }

                    // Recent Meals
                    if !store.todayMeals.isEmpty {
                        GlassCard {
                            VStack(spacing: Theme.spacing.md) {
                                SectionHeader("Recent Meals", showChevron: true)

                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(store.todayMeals.prefix(3)) { meal in
                                        MealRow(
                                            title: meal.items.first?.name ?? "Meal",
                                            kcal: meal.totals.kcal,
                                            time: meal.timestamp.formatted(date: .omitted, time: .shortened)
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Latest Weight
                    if let weightKg = store.latestWeight {
                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Latest Weight")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                    Text(String(format: "%.1f kg", weightKg))
                                        .font(.title.bold())
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                Spacer()
                                // You could add trend indicator here
                                Text("↓ 0.5 kg")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
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
        .navigationBarHidden(true)
    }
    
    private func loadTodayStats() async {
        await store.refreshTodayStats(apiClient: apiClient)
    }
}