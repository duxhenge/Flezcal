import SwiftUI

// MARK: - Preference Key for Tutorial Targets

struct TutorialTargetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Registers this view as a tutorial target that can be spotlighted.
    /// Uses transformAnchorPreference so nested targets (parent + child) both propagate.
    func tutorialTarget(_ id: String) -> some View {
        self.transformAnchorPreference(key: TutorialTargetKey.self, value: .bounds) { current, anchor in
            current[id] = anchor
        }
    }
}

// MARK: - Reverse Mask

extension View {
    /// Masks the view with a cutout — the provided shape is removed from the mask.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .ignoresSafeArea()
                .overlay {
                    mask()
                        .blendMode(.destinationOut)
                }
        }
    }
}

// MARK: - Tutorial Overlay

/// Full-screen overlay that shows tutorial steps — spotlight for live targets,
/// centered card for screenshot-only steps.
struct TutorialOverlay: View {
    @ObservedObject var tutorialService: TutorialService

    var body: some View {
        if tutorialService.isActive, let step = tutorialService.currentStep {
            ZStack {
                if let targetID = step.targetID,
                   let frame = tutorialService.targetFrames[targetID] {
                    // Live spotlight step
                    spotlightView(step: step, targetFrame: frame)
                } else if step.screenshotImage != nil || step.targetID == nil {
                    // Screenshot or text-only step — centered card
                    screenshotView(step: step)
                } else if step.targetID != nil {
                    // Live step but target not yet reported — show dimmed waiting state
                    // with a skip button so the user isn't trapped if the target never appears.
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .allowsHitTesting(true)

                    VStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Text("Loading…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 8)
                        Spacer()
                        Button("Exit Tutorial") { tutorialService.skip() }
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.bottom, 60)
                    }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: tutorialService.currentStepIndex)
        }
    }

    // MARK: - Live Spotlight

    @ViewBuilder
    private func spotlightView(step: TutorialStep, targetFrame: CGRect) -> some View {
        // Dimmed background with cutout
        SpotlightBackground(targetFrame: targetFrame, shape: step.spotlightShape)

        // Step card positioned relative to the target
        TutorialStepCard(
            step: step,
            stepNumber: tutorialService.currentStepIndex + 1,
            totalSteps: tutorialService.stepCount,
            targetFrame: targetFrame,
            onBack: { tutorialService.previousStep() },
            onNext: { tutorialService.nextStep() },
            onSkip: { tutorialService.skip() }
        )
    }

    // MARK: - Screenshot Card

    @ViewBuilder
    private func screenshotView(step: TutorialStep) -> some View {
        // Full dim — no cutout
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .allowsHitTesting(true)

        // Centered card with screenshot
        ScreenshotStepCard(
            step: step,
            stepNumber: tutorialService.currentStepIndex + 1,
            totalSteps: tutorialService.stepCount,
            onBack: { tutorialService.previousStep() },
            onNext: { tutorialService.nextStep() },
            onSkip: { tutorialService.skip() }
        )
    }
}

// MARK: - Spotlight Background

private struct SpotlightBackground: View {
    let targetFrame: CGRect
    let shape: TutorialStep.SpotlightShape

    private let padding: CGFloat = 8

    var body: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .reverseMask {
                switch shape {
                case .rect(let cr):
                    RoundedRectangle(cornerRadius: cr)
                        .frame(width: targetFrame.width + padding * 2,
                               height: targetFrame.height + padding * 2)
                        .position(x: targetFrame.midX, y: targetFrame.midY)
                case .capsule:
                    Capsule()
                        .frame(width: targetFrame.width + padding * 2,
                               height: targetFrame.height + padding * 2)
                        .position(x: targetFrame.midX, y: targetFrame.midY)
                case .circle:
                    Circle()
                        .frame(width: max(targetFrame.width, targetFrame.height) + padding * 2)
                        .position(x: targetFrame.midX, y: targetFrame.midY)
                case .none:
                    EmptyView()
                }
            }
            .allowsHitTesting(true)
    }
}

// MARK: - Tutorial Step Card (positioned near target)

private struct TutorialStepCard: View {
    let step: TutorialStep
    let stepNumber: Int
    let totalSteps: Int
    let targetFrame: CGRect
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    /// Measured card height — updated via background GeometryReader.
    @State private var cardHeight: CGFloat = 160  // reasonable initial estimate

    /// Spacing between the spotlight cutout edge and the card edge.
    private let spotlightPadding: CGFloat = 8  // matches SpotlightBackground.padding
    private let cardSpacing: CGFloat = 20
    private let arrowHeight: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let screenHeight = geo.size.height
            let cardWidth: CGFloat = min(320, screenWidth - 32)

            // Space available above and below the spotlight cutout (including padding)
            let spotlightTop = targetFrame.minY - spotlightPadding
            let spotlightBottom = targetFrame.maxY + spotlightPadding
            let spaceAbove = spotlightTop
            let spaceBelow = screenHeight - spotlightBottom
            let neededSpace = cardHeight + cardSpacing + arrowHeight

            // Place below if there's enough room, or if explicitly requested and fits,
            // or if neither side fits but below has more room
            let placeBelow: Bool = {
                if step.arrowEdge == .top && spaceBelow >= neededSpace {
                    return true
                }
                if step.arrowEdge == .bottom && spaceAbove >= neededSpace {
                    return false
                }
                // Default: pick whichever side has more room
                return spaceBelow >= spaceAbove
            }()

            // Horizontal: center on target, clamp to screen edges
            let cardX = max(16, min(screenWidth - cardWidth - 16,
                                    targetFrame.midX - cardWidth / 2))

            // Vertical: anchor the card edge at the spotlight edge + spacing,
            // then clamp so the entire card stays on screen.
            let cardCenterX = cardX + cardWidth / 2
            let halfCard = cardHeight / 2

            let cardCenterY: CGFloat = {
                if placeBelow {
                    // Card top edge sits at spotlightBottom + arrowHeight + cardSpacing
                    let topEdge = spotlightBottom + arrowHeight + cardSpacing
                    let centerY = topEdge + halfCard
                    // Clamp: card bottom must not exceed screen bottom - 16
                    let maxCenter = screenHeight - 16 - halfCard
                    return min(centerY, maxCenter)
                } else {
                    // Card bottom edge sits at spotlightTop - arrowHeight - cardSpacing
                    let bottomEdge = spotlightTop - arrowHeight - cardSpacing
                    let centerY = bottomEdge - halfCard
                    // Clamp: card top must not go above 16
                    let minCenter: CGFloat = 16 + halfCard
                    return max(centerY, minCenter)
                }
            }()

            cardContent
                .frame(width: cardWidth)
                .background(
                    GeometryReader { cardGeo in
                        Color.clear
                            .onAppear { cardHeight = cardGeo.size.height }
                            .onChange(of: cardGeo.size.height) { _, h in cardHeight = h }
                    }
                )
                .position(x: cardCenterX, y: cardCenterY)

            // Arrow triangle — sits between spotlight edge and card edge
            arrowTriangle(pointingUp: placeBelow)
                .position(
                    x: max(32, min(screenWidth - 32, targetFrame.midX)),
                    y: placeBelow
                        ? spotlightBottom + arrowHeight / 2 + 4
                        : spotlightTop - arrowHeight / 2 - 4
                )
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step \(stepNumber) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(step.title)
                .font(.headline)
                .fontWeight(.bold)

            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if stepNumber > 1 {
                    Button {
                        onBack()
                    } label: {
                        Text("Back")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button("Exit") { onSkip() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onNext()
                } label: {
                    Text(stepNumber == totalSteps ? "Done" : "Next")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
    }

    @State private var arrowBounce: CGFloat = 0

    private func arrowTriangle(pointingUp: Bool) -> some View {
        Triangle()
            .fill(Color(.systemBackground))
            .frame(width: 20, height: 10)
            .rotationEffect(.degrees(pointingUp ? 0 : 180))
            .shadow(color: .black.opacity(0.15), radius: 4, y: pointingUp ? -2 : 2)
            .offset(y: arrowBounce)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    arrowBounce = pointingUp ? -4 : 4
                }
            }
    }
}

// MARK: - Screenshot Step Card (centered)

private struct ScreenshotStepCard: View {
    let step: TutorialStep
    let stepNumber: Int
    let totalSteps: Int
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(stepNumber) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(step.title)
                .font(.headline)
                .fontWeight(.bold)

            // Screenshot image — cropped to region of interest when specified
            if let imageName = step.screenshotImage,
               let uiImage = UIImage(named: imageName) {
                if let crop = step.screenshotCropRegion {
                    CroppedScreenshot(uiImage: uiImage, cropRegion: crop)
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if stepNumber > 1 {
                    Button {
                        onBack()
                    } label: {
                        Text("Back")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button("Exit") { onSkip() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onNext()
                } label: {
                    Text(stepNumber == totalSteps ? "Done" : "Next")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
    }
}

// MARK: - Cropped Screenshot

/// Crops a UIImage to the specified unit-coordinate region (0–1) and displays it
/// so it always fills the available frame height (280pt), regardless of aspect ratio.
private struct CroppedScreenshot: View {
    let uiImage: UIImage
    /// Unit-coordinate rect (0–1). Example: CGRect(x: 0, y: 0.03, width: 1, height: 0.25)
    let cropRegion: CGRect

    private let displayHeight: CGFloat = 280

    var body: some View {
        if let cropped = croppedImage() {
            let imgAspect = CGFloat(cropped.cgImage?.width ?? 1) / CGFloat(cropped.cgImage?.height ?? 1)
            // Width that fills the height at native aspect ratio
            let displayWidth = displayHeight * imgAspect

            Image(uiImage: cropped)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: min(displayWidth, 320), height: displayHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private func croppedImage() -> UIImage? {
        guard let cgImage = uiImage.cgImage else { return nil }
        let fullWidth = CGFloat(cgImage.width)
        let fullHeight = CGFloat(cgImage.height)

        let pixelRect = CGRect(
            x: cropRegion.origin.x * fullWidth,
            y: cropRegion.origin.y * fullHeight,
            width: cropRegion.width * fullWidth,
            height: cropRegion.height * fullHeight
        )

        guard let croppedCG = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: uiImage.scale, orientation: uiImage.imageOrientation)
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
