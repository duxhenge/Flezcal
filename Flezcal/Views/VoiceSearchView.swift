import SwiftUI
import CoreLocation

/// Drop this view wherever your search bar lives.
/// It publishes a resolved VoiceQuery back to the parent via onQuery.
struct VoiceSearchView: View {

    // Injected from parent — fires when a valid query is ready to execute
    var onQuery: (VoiceQuery) -> Void

    @StateObject private var voice = VoiceSearchManager()
    @State private var pendingQuery: VoiceQuery? = nil       // waiting for "did you mean" confirm
    @State private var showDidYouMean: Bool = false
    @State private var showHelp: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {

            // Live transcript bubble
            if voice.isListening || !voice.transcript.isEmpty {
                transcriptBubble
            }

            // Mic button
            micButton

            // Error
            if let error = voice.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            // Help hint
            if showHelp {
                helpHints
            }
        }
        .onAppear {
            voice.requestPermissions()
            voice.onFinalTranscript = handleTranscript(_:)
        }
        // "Did you mean" sheet
        .confirmationDialog(didYouMeanTitle, isPresented: $showDidYouMean, titleVisibility: .visible) {
            if let query = pendingQuery {
                ForEach(query.categorySuggestions, id: \.self) { suggestion in
                    Button(suggestion.capitalized) {
                        // Re-parse with the confirmed category substituted in
                        let corrected = QueryParser.parse(suggestion + " " + query.rawTranscript)
                        onQuery(corrected)
                    }
                }
                Button("Search anyway", role: .destructive) {
                    if let q = pendingQuery { onQuery(q) }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        // Permissions denied alert
        .alert("Microphone Access Required",
               isPresented: $voice.permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(AppBranding.name) needs microphone access to use voice search.")
        }
    }

    // MARK: - Subviews

    private var micButton: some View {
        Button(action: { voice.startListening() }) {
            ZStack {
                Circle()
                    .fill(voice.isListening ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(voice.isListening ? .red : .accentColor)
                    .symbolEffect(.pulse, isActive: voice.isListening)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { withAnimation { showHelp.toggle() } }) {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .offset(x: 4, y: -4)
        }
    }

    private var transcriptBubble: some View {
        Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
            .font(.subheadline)
            .foregroundColor(voice.transcript.isEmpty ? .secondary : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .animation(.easeInOut, value: voice.transcript)
    }

    private var helpHints: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try saying:")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(exampleCommands, id: \.self) { example in
                Label(example, systemImage: "mic")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Logic

    private func handleTranscript(_ raw: String) {
        let query = QueryParser.parse(raw)

        switch query.command {
        case .unrecognized:
            if !query.categorySuggestions.isEmpty {
                // Have fuzzy suggestions → show "did you mean"
                pendingQuery = query
                showDidYouMean = true
            } else {
                // Nothing found → show help hints
                withAnimation { showHelp = true }
                voice.error = "Try saying something like 'craft beer in Worcester'."
            }

        case .locationOnly where !query.categorySuggestions.isEmpty:
            // Location found but category was a near-miss
            pendingQuery = query
            showDidYouMean = true

        default:
            onQuery(query)
        }
    }

    private var didYouMeanTitle: String {
        guard let q = pendingQuery, !q.categorySuggestions.isEmpty else {
            return "Did you mean…"
        }
        return "Did you mean \(q.categorySuggestions.first?.capitalized ?? "")?"
    }

    private let exampleCommands = [
        "\"Craft beer in Worcester\"",
        "\"Mezcal near me\"",
        "\"What's in Austin?\"",
        "\"Find Taqueria El Rancho\""
    ]
}
