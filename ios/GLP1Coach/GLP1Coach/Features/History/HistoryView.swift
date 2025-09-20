import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var entries: [HistoryEntryResp] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: HistoryEntryResp.EntryType? = nil
    @State private var entryToDelete: HistoryEntryResp? = nil
    @State private var showingDeleteConfirmation = false
    @State private var sortOrder: SortOrder = .newestFirst
    @State private var isSelectionMode = false
    @State private var selectedEntries: Set<String> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var expandedEntries: Set<String> = []
    
    enum SortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        
        var systemImage: String {
            switch self {
            case .newestFirst: return "arrow.down"
            case .oldestFirst: return "arrow.up"
            }
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea(.all)

            VStack {
                // Hero Title
                Text("History")
                    .font(.heroTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Filter buttons
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                FilterButton(title: "All", isSelected: selectedFilter == nil) {
                                    selectedFilter = nil
                                    Task { await loadHistory() }
                                }
                                
                                ForEach(HistoryEntryResp.EntryType.allCases, id: \.self) { type in
                                    FilterButton(
                                        title: type.displayName,
                                        isSelected: selectedFilter == type,
                                        icon: type.icon
                                    ) {
                                        selectedFilter = type
                                        Task { await loadHistory() }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 10)
                        
                        // Sort picker and controls
                        HStack {
                            if !isSelectionMode {
                                Text("Sort by:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Picker("Sort Order", selection: $sortOrder) {
                                    ForEach(SortOrder.allCases, id: \.self) { order in
                                        HStack {
                                            Image(systemName: order.systemImage)
                                            Text(order.rawValue)
                                        }
                                        .tag(order)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: sortOrder) { _, _ in
                                    sortEntries()
                                }
                            } else {
                                Text("\(selectedEntries.count) selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if !selectedEntries.isEmpty {
                                    Button("Delete Selected") {
                                        showingBulkDeleteConfirmation = true
                                    }
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                            }

                            Spacer()

                            Button(isSelectionMode ? "Cancel" : "Select") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSelectionMode.toggle()
                                    if !isSelectionMode {
                                        selectedEntries.removeAll()
                                    }
                                }
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(isSelectionMode ? .red : .accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelectionMode ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        
                        // History list
                        if entries.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "clock")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text("No entries found")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Your logged meals, exercises, and weights will appear here")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    ForEach(entries) { entry in
                                    HistoryEntryRow(
                                        entry: entry,
                                        onDelete: {
                                            entryToDelete = entry
                                            showingDeleteConfirmation = true
                                        },
                                        isSelectionMode: isSelectionMode,
                                        isSelected: selectedEntries.contains(entry.id),
                                        onSelectionToggle: {
                                            if selectedEntries.contains(entry.id) {
                                                selectedEntries.remove(entry.id)
                                            } else {
                                                selectedEntries.insert(entry.id)
                                            }
                                        },
                                        isExpanded: expandedEntries.contains(entry.id),
                                        onExpandToggle: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                                if expandedEntries.contains(entry.id) {
                                                    expandedEntries.remove(entry.id)
                                                } else {
                                                    expandedEntries.insert(entry.id)
                                                }
                                            }
                                        }
                                    )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .refreshable {
                                // Exit selection mode during refresh to avoid state conflicts
                                if isSelectionMode {
                                    isSelectionMode = false
                                    selectedEntries.removeAll()
                                }
                                expandedEntries.removeAll()
                                await loadHistory()
                            }
                        }
                    }
                }
            }
            .task {
                await loadHistory()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Delete Entry", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    entryToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete {
                        Task { await deleteEntry(entry) }
                    }
                }
            } message: {
                if let entry = entryToDelete {
                    Text("Are you sure you want to delete this \(entry.type.displayName.lowercased()) entry? This action cannot be undone.")
                }
            }
            .alert("Delete Selected Items", isPresented: $showingBulkDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    // Keep selection
                }
                Button("Delete \(selectedEntries.count) Items", role: .destructive) {
                    Task { await deleteSelectedEntries() }
                }
            } message: {
                Text("Are you sure you want to delete \(selectedEntries.count) selected entries? This action cannot be undone.")
            }
        }
        .tapToDismissKeyboard()
    }
    
    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await apiClient.getHistory(
                typeFilter: selectedFilter?.rawValue
            )
            await MainActor.run {
                entries = response.entries
                sortEntries()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load history: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func sortEntries() {
        switch sortOrder {
        case .newestFirst:
            entries.sort { $0.ts > $1.ts }
        case .oldestFirst:
            entries.sort { $0.ts < $1.ts }
        }
    }

    private func deleteEntry(_ entry: HistoryEntryResp) async {
        do {
            print("🗑️ Attempting to delete entry: \(entry.id) of type: \(entry.type.rawValue)")
            try await apiClient.deleteEntry(entryType: entry.type.rawValue, entryId: entry.id)
            print("✅ Delete successful for entry: \(entry.id)")
            await MainActor.run {
                entries.removeAll { $0.id == entry.id }
                entryToDelete = nil
            }
        } catch {
            print("❌ Delete failed for entry: \(entry.id), error: \(error)")
            await MainActor.run {
                errorMessage = "Failed to delete entry: \(error.localizedDescription)"
                entryToDelete = nil
            }
        }
    }

    private func deleteSelectedEntries() async {
        let selectedEntriesToDelete = entries.filter { selectedEntries.contains($0.id) }
        var deletedCount = 0
        var failedCount = 0

        for entry in selectedEntriesToDelete {
            do {
                print("🗑️ Bulk deleting entry: \(entry.id) of type: \(entry.type.rawValue)")
                try await apiClient.deleteEntry(entryType: entry.type.rawValue, entryId: entry.id)
                print("✅ Bulk delete successful for entry: \(entry.id)")
                deletedCount += 1

                await MainActor.run {
                    entries.removeAll { $0.id == entry.id }
                }
            } catch {
                print("❌ Bulk delete failed for entry: \(entry.id), error: \(error)")
                failedCount += 1
            }
        }

        await MainActor.run {
            selectedEntries.removeAll()
            isSelectionMode = false

            if failedCount > 0 {
                errorMessage = "Deleted \(deletedCount) entries. Failed to delete \(failedCount) entries."
            }
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let icon: String?
    let action: () -> Void
    
    init(title: String, isSelected: Bool, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

struct HistoryEntryRow: View {
    let entry: HistoryEntryResp
    let onDelete: () -> Void
    let isSelectionMode: Bool
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    let isExpanded: Bool
    let onExpandToggle: () -> Void


    var body: some View {
        VStack(spacing: 0) {
            // Main row - always visible
            HStack(spacing: 12) {
                // Selection checkbox (when in selection mode)
                if isSelectionMode {
                    Button {
                        onSelectionToggle()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(isSelected ? .blue : .gray)
                    }
                    .buttonStyle(.plain)
                }

                // Icon
                Image(systemName: entry.type.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(entry.display_name)
                        .font(.headline)
                        .lineLimit(2)

                    // Timestamp
                    Text(entry.ts.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Summary details
                    Text(summaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Expand chevron (for meals and exercises)
                if entry.type == .meal || entry.type == .exercise {
                    Button {
                        onExpandToggle()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())

            // Expanded details - for meals and exercises
            if isExpanded && entry.type == .meal {
                VStack(alignment: .leading, spacing: 0) {
                    // Food items list
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(mealItems.enumerated()), id: \.element.name) { index, item in
                            HStack {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.blue.opacity(0.6))
                                        .frame(width: 6, height: 6)

                                    Text(item.name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }

                                Spacer()

                                Text("\(item.kcal) kcal")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Total row with enhanced styling
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "sum")
                                    .font(.caption)
                                    .foregroundColor(.blue)

                                Text("Total")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }

                            Spacer()

                            Text("\(totalCalories) kcal")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 2)
                }
            }

            // Expanded details - for exercises
            if isExpanded && entry.type == .exercise {
                VStack(alignment: .leading, spacing: 8) {
                    // Exercise details
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.orange.opacity(0.6))
                                    .frame(width: 6, height: 6)

                                Text("Duration")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }

                            Spacer()

                            Text(exerciseDuration)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                        if let caloriesBurned = exerciseCalories {
                            HStack {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.red.opacity(0.6))
                                        .frame(width: 6, height: 6)

                                    Text("Calories Burned")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }

                                Spacer()

                                Text("\(caloriesBurned) kcal")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 2)
            }
        }
        .onTapGesture {
            if (entry.type == .meal || entry.type == .exercise) && !isSelectionMode {
                onExpandToggle()
            } else if isSelectionMode {
                onSelectionToggle()
            }
        }
        .onLongPressGesture {
            onDelete()
        }
    }

    // Helper properties for meal expansion
    private var mealItems: [(name: String, kcal: Int)] {
        guard entry.type == .meal else { return [] }
        let items = entry.details["items"] as? [[String: Any]] ?? []
        return items.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let kcal = dict["kcal"] as? Int else { return nil }
            return (name: name, kcal: kcal)
        }
    }

    private var totalCalories: Int {
        entry.details["total_kcal"] as? Int ?? mealItems.reduce(0) { $0 + $1.kcal }
    }

    // Helper properties for exercise expansion
    private var exerciseDuration: String {
        guard entry.type == .exercise else { return "" }
        let duration = (entry.details["duration_min"] as? Double) ??
                      Double(entry.details["duration_min"] as? Int ?? 0)
        return "\(Int(duration)) minutes"
    }

    private var exerciseCalories: Int? {
        guard entry.type == .exercise else { return nil }
        return (entry.details["est_kcal"] as? Int) ??
               (entry.details["est_kcal"] as? Double).map { Int($0) }
    }

    private var summaryText: String {
        switch entry.type {
        case .meal:
            return "\(mealItems.count) items • \(totalCalories) kcal"

        case .exercise:
            // Handle both Int and Double for duration
            let duration = (entry.details["duration_min"] as? Double) ??
                          Double(entry.details["duration_min"] as? Int ?? 0)
            // Handle both Int and Double for calories
            let kcal = (entry.details["est_kcal"] as? Int) ??
                      (entry.details["est_kcal"] as? Double).map { Int($0) }
            if let kcal = kcal {
                return "\(Int(duration))min • \(kcal) kcal burned"
            } else {
                return "\(Int(duration)) minutes"
            }

        case .weight:
            // Handle both Int and Double for weight_kg
            let weight = (entry.details["weight_kg"] as? Double) ??
                        Double(entry.details["weight_kg"] as? Int ?? 0)
            return "\(String(format: "%.1f", weight)) kg"

        case .medication:
            return "Medication dose"
        }
    }
}


#Preview {
    HistoryView()
        .environmentObject(APIClient())
}
