import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var entries: [HistoryEntryResp] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: HistoryEntryResp.EntryType? = nil
    @State private var selectedEntry: HistoryEntryResp? = nil
    @State private var showingEditSheet = false
    @State private var sortOrder: SortOrder = .newestFirst
    
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
        NavigationView {
            VStack {
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
                        
                        // Sort picker
                        HStack {
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
                            .onChange(of: sortOrder) {
                                sortEntries()
                            }
                            
                            Spacer()
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
                            List {
                                ForEach(entries) { entry in
                                    HistoryEntryRow(entry: entry) {
                                        selectedEntry = entry
                                        showingEditSheet = true
                                    }
                                }
                            }
                            .refreshable {
                                await loadHistory()
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .task {
                await loadHistory()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingEditSheet) {
                if let entry = selectedEntry {
                    EditEntrySheet(entry: entry) {
                        showingEditSheet = false
                        selectedEntry = nil
                        Task { await loadHistory() }
                    }
                    .environmentObject(apiClient)
                }
            }
        }
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
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: entry.type.icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(entry.display_name)
                    .font(.headline)
                    .lineLimit(1)
                
                // Timestamp
                Text(entry.ts.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Details
                Text(detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Edit button
            Button("Edit", action: onEdit)
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
    
    private var detailText: String {
        switch entry.type {
        case .meal:
            let items = entry.details["items"] as? [[String: Any]] ?? []
            let totalKcal = entry.details["total_kcal"] as? Int ?? 0
            return "\(items.count) items • \(totalKcal) kcal"
            
        case .exercise:
            let duration = entry.details["duration_min"] as? Double ?? 0
            let kcal = entry.details["est_kcal"] as? Int
            if let kcal = kcal {
                return "\(Int(duration))min • \(kcal) kcal burned"
            } else {
                return "\(Int(duration)) minutes"
            }
            
        case .weight:
            let weight = entry.details["weight_kg"] as? Double ?? 0
            return "\(String(format: "%.1f", weight)) kg"
            
        case .medication:
            return "Medication dose"
        }
    }
}

struct EditEntrySheet: View {
    let entry: HistoryEntryResp
    let onSave: () -> Void
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch entry.type {
                    case .meal:
                        EditMealView(entry: entry, onSave: handleSave)
                    case .exercise:
                        EditExerciseView(entry: entry, onSave: handleSave)
                    case .weight:
                        EditWeightView(entry: entry, onSave: handleSave)
                    case .medication:
                        Text("Medication editing not yet implemented")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Edit \(entry.type.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    private func handleSave() async {
        isLoading = true
        await MainActor.run {
            onSave()
            dismiss()
        }
    }
}

// Individual edit views would be implemented here
struct EditMealView: View {
    let entry: HistoryEntryResp
    let onSave: () async -> Void
    @State private var notes: String = ""
    
    var body: some View {
        VStack {
            Text("Meal editing coming soon")
                .foregroundColor(.secondary)
            
            Button("Save Changes") {
                Task { await onSave() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct EditExerciseView: View {
    let entry: HistoryEntryResp
    let onSave: () async -> Void
    @State private var exerciseType: String = ""
    @State private var duration: Double = 0
    
    var body: some View {
        VStack {
            Text("Exercise editing coming soon")
                .foregroundColor(.secondary)
            
            Button("Save Changes") {
                Task { await onSave() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct EditWeightView: View {
    let entry: HistoryEntryResp  
    let onSave: () async -> Void
    @State private var weight: Double = 0
    
    var body: some View {
        VStack {
            Text("Weight editing coming soon")
                .foregroundColor(.secondary)
            
            Button("Save Changes") {
                Task { await onSave() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    HistoryView()
        .environmentObject(APIClient())
}
