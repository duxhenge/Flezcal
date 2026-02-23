import SwiftUI

struct WelcomeView: View {
    @StateObject private var service = WelcomeService()
    let onDismiss: (String) -> Void  // passes the version back so caller can persist it

    var body: some View {
        ZStack {
            if service.isLoading {
                loadingView
            } else if let content = service.content {
                contentView(content)
            }
        }
        .task {
            await service.fetchWelcomeContent()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Text("🍮")
                .font(.system(size: 60))
            ProgressView()
                .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private func contentView(_ content: WelcomeContent) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                        // Side-by-side hero: photo + flan emoji
                        HStack(spacing: 16) {
                            Image("WelcomeHero")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            Text("🍮")
                                .font(.system(size: 90))
                                .frame(width: 120, height: 120)
                        }
                        .padding(.top, 32)

                        // Title & subtitle
                        VStack(spacing: 10) {
                            Text(content.title)
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)

                            Text(content.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Feature / update bullets
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(content.items) { item in
                                WelcomeItemRow(item: item)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Footer — only shown when non-empty
                        if !content.footer.isEmpty {
                            Text(content.footer)
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 8)
                        }
                }
                .padding(.bottom, 100) // leave room for the fixed button
            }

            // Fixed dismiss button pinned to bottom
            VStack(spacing: 0) {
                Divider()
                Button {
                    onDismiss(content.version)
                } label: {
                    Text("Let's go! 🍮")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding()
                }
                .background(Color(.systemBackground))
            }
        }
    }
}

// MARK: - Bullet Row

private struct WelcomeItemRow: View {
    let item: WelcomeItem

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)

            Text(item.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    WelcomeView { _ in }
}
