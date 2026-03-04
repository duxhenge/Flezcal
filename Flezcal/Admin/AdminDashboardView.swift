import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject var spotService: SpotService
    @StateObject private var viewModel = AdminViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                AdminOverviewView(viewModel: viewModel)
                    .tabItem { Label("Overview", systemImage: "chart.bar") }
                    .tag(0)

                AdminRevenueView(viewModel: viewModel)
                    .tabItem { Label("Revenue", systemImage: "dollarsign.circle") }
                    .tag(1)

                AdminCostsView(viewModel: viewModel)
                    .tabItem { Label("Costs", systemImage: "creditcard") }
                    .tag(2)

                AdminDeadlinesView(viewModel: viewModel)
                    .tabItem { Label("Deadlines", systemImage: "calendar.badge.clock") }
                    .tag(3)

                AdminNotesView(viewModel: viewModel)
                    .tabItem { Label("Notes", systemImage: "note.text") }
                    .tag(4)

                AdminClosureReportsView(viewModel: viewModel)
                    .tabItem { Label("Closures", systemImage: "exclamationmark.triangle") }
                    .tag(5)
            }
            .tint(.orange)
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }
}
