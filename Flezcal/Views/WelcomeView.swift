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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading welcome screen")
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
                                .accessibilityHidden(true)

                            Text("🍮")
                                .font(.system(size: 90))
                                .frame(width: 120, height: 120)
                                .accessibilityHidden(true)
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
                        .accessibilityElement(children: .combine)

                        // What is Flezcal?
                        if !content.tagline.isEmpty {
                            VStack(spacing: 8) {
                                Text("What is Flezcal?")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Text(content.tagline)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 24)
                            .accessibilityElement(children: .combine)
                        }

                        // Feature / update bullets
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(content.items) { item in
                                WelcomeItemRow(item: item)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Feature walkthrough cards
                        if !content.pages.isEmpty {
                            VStack(spacing: 16) {
                                ForEach(content.pages) { page in
                                    WelcomePageCard(page: page)
                                }
                            }
                            .padding(.horizontal, 24)
                        }

                        // Own a Spot? card
                        WelcomeInfoCard(
                            icon: "storefront",
                            tint: .orange,
                            headline: "Own a Spot?",
                            message: "If you own or manage a place that serves great food or drinks, add your spot and update your offerings just like any other user, for free. "
                                + "Want a verified badge, locked menu details, and a reservation link? Contact us about Owner Verification.",
                            linkText: "Contact us at contact@flezcal.app",
                            linkURL: "mailto:contact@flezcal.app"
                        )
                        .padding(.horizontal, 24)

                        // Shape Flezcal card
                        WelcomeShapeCard()
                            .padding(.horizontal, 24)

                        // Change note — shown when the welcome screen reappears after an update
                        if !content.changeNote.isEmpty {
                            VStack(spacing: 6) {
                                if !content.changeDate.isEmpty {
                                    Text("Updated \(content.changeDate)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.orange)
                                }
                                Text(content.changeNote)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                            .accessibilityElement(children: .combine)
                        }

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
                .accessibilityLabel("Dismiss welcome screen")
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
                .accessibilityHidden(true)

            Text(item.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Feature Page Card

private struct WelcomePageCard: View {
    let page: WelcomePage

    private var tint: Color {
        switch page.color {
        case "orange": return .orange
        case "blue":   return .blue
        case "pink":   return .pink
        case "green":  return .green
        case "purple": return .purple
        case "red":    return .red
        default:       return .orange
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: page.icon)
                .font(.system(size: 36))
                .foregroundStyle(tint)
                .frame(height: 44)
                .accessibilityHidden(true)

            Text(page.headline)
                .font(.headline)
                .fontWeight(.bold)

            Text(page.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Info Card (used for "Own a Spot?")

private struct WelcomeInfoCard: View {
    let icon: String
    let tint: Color
    let headline: String
    let message: String
    var linkText: String? = nil
    var linkURL: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(tint)
                .frame(height: 44)
                .accessibilityHidden(true)

            Text(headline)
                .font(.headline)
                .fontWeight(.bold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let linkText, let linkURL, let url = URL(string: linkURL) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .font(.caption)
                        Text(linkText)
                            .font(.footnote)
                    }
                    .foregroundStyle(.orange)
                }
                .accessibilityLabel(linkText)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shape Flezcal Card

private struct WelcomeShapeCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 36))
                .foregroundStyle(.yellow)
                .frame(height: 44)
                .accessibilityHidden(true)

            Text("Shape Flezcal")
                .font(.headline)
                .fontWeight(.bold)

            Text("Flezcal grows with its community. The categories you search for, the spots you add, the ratings you leave, all of it shapes what comes next. Have an idea? We're listening.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Email link
            Link(destination: URL(string: "mailto:contact@flezcal.app")!) {
                HStack(spacing: 6) {
                    Image(systemName: "envelope.fill")
                        .font(.caption)
                    Text("Tell us at contact@flezcal.app")
                        .font(.footnote)
                }
                .foregroundStyle(.orange)
            }
            .accessibilityLabel("Email contact at contact@flezcal.app")
            .padding(.top, 4)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    WelcomeView { _ in }
}
