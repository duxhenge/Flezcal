import SwiftUI

/// Custom veladora (mezcal glass) icon drawn as a SwiftUI vector.
/// Ribbed straight-sided veladora tumbler, orange wedge left, sal de gusano mound right.
///
/// **Minimum safe size: 16pt.** Below that, Canvas geometry calculations can produce
/// NaN values that freeze CoreGraphics. Falls back to emoji at tiny sizes.
struct VeladoraIcon: View {
    var size: CGFloat = 28

    /// Below this threshold, Canvas geometry produces NaN values that crash CoreGraphics.
    private static let minimumCanvasSize: CGFloat = 14

    var body: some View {
        if size < Self.minimumCanvasSize {
            // Emoji fallback — avoids NaN from Canvas geometry at very small sizes
            Text("🥃")
                .font(.system(size: size * 0.75))
                .frame(width: size, height: size)
        } else {
            canvasIcon
        }
    }

    private var canvasIcon: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // ── Glass geometry: straight sides, shorter (half height of before)
            // Base width unchanged; rim is wider (same proportional taper)
            let baseY:    CGFloat = h * 0.88
            let rimY:     CGFloat = baseY - (h * 0.40)   // half the original ~0.80 span
            let baseLeft: CGFloat = w * 0.31
            let baseRight:CGFloat = w * 0.69
            let rimLeft:  CGFloat = w * 0.25
            let rimRight: CGFloat = w * 0.75

            // ── Glass outline only — no fill, no color ────────────────────────
            let outlineColor = Color(red: 0.45, green: 0.35, blue: 0.20)

            var glassFill = Path()
            glassFill.move(to: CGPoint(x: rimLeft,   y: rimY))
            glassFill.addLine(to: CGPoint(x: rimRight,  y: rimY))
            glassFill.addLine(to: CGPoint(x: baseRight, y: baseY))
            glassFill.addLine(to: CGPoint(x: baseLeft,  y: baseY))
            glassFill.closeSubpath()
            // No fill — transparent glass
            context.stroke(glassFill, with: .color(outlineColor.opacity(0.85)),
                           lineWidth: max(0.8, w * 0.032))

            // ── Vertical ribs (straight lines) ────────────────────────────────
            let ribCount = 8
            for i in 1..<ribCount {
                let f    = CGFloat(i) / CGFloat(ribCount)
                let topX = rimLeft  + (rimRight  - rimLeft)  * f
                let botX = baseLeft + (baseRight - baseLeft) * f
                var rib  = Path()
                rib.move(to: CGPoint(x: topX, y: rimY + h*0.01))
                rib.addLine(to: CGPoint(x: botX, y: baseY - h*0.01))
                context.stroke(rib, with: .color(outlineColor.opacity(0.28)),
                               lineWidth: max(0.4, w * 0.016))
            }

            // ── Mezcal fill line at 3/4 height of glass ───────────────────────
            let fillFraction: CGFloat = 0.25   // 1/4 from top = 3/4 full
            let fillY    = rimY + (baseY - rimY) * fillFraction
            let tFill    = (fillY - rimY) / (baseY - rimY)
            let fillLeft = rimLeft  + (baseLeft  - rimLeft)  * tFill + w * 0.012
            let fillRight = rimRight + (baseRight - rimRight) * tFill - w * 0.012

            var fillLine = Path()
            fillLine.move(to: CGPoint(x: fillLeft,  y: fillY))
            fillLine.addLine(to: CGPoint(x: fillRight, y: fillY))
            context.stroke(fillLine, with: .color(outlineColor.opacity(0.60)),
                           lineWidth: max(0.5, w * 0.022))

            // ── Orange wedge (left, leaning against glass) ────────────────────
            let orCx: CGFloat = w * 0.14
            let orCy: CGFloat = h * 0.68
            let orR:  CGFloat = w * 0.20

            var orangePath = Path()
            let startAngle = Angle.degrees(-20)
            let endAngle   = Angle.degrees(200)
            orangePath.move(to: CGPoint(x: orCx, y: orCy))
            orangePath.addArc(center: CGPoint(x: orCx, y: orCy),
                              radius: orR,
                              startAngle: startAngle,
                              endAngle: endAngle,
                              clockwise: false)
            orangePath.closeSubpath()
            context.fill(orangePath, with: .color(Color(red: 1.0, green: 0.62, blue: 0.10)))
            context.stroke(orangePath, with: .color(Color(red: 0.85, green: 0.38, blue: 0.04)),
                           lineWidth: max(0.8, w * 0.030))

            // Segment lines
            let segCount = 6
            for i in 0..<segCount {
                let angle = startAngle.radians + (endAngle.radians - startAngle.radians) * Double(i) / Double(segCount)
                var seg = Path()
                seg.move(to: CGPoint(x: orCx, y: orCy))
                seg.addLine(to: CGPoint(x: orCx + CGFloat(cos(angle)) * orR,
                                        y: orCy + CGFloat(sin(angle)) * orR))
                context.stroke(seg, with: .color(Color(red: 0.85, green: 0.38, blue: 0.04).opacity(0.50)),
                               lineWidth: max(0.4, w * 0.013))
            }

            // White pith center
            var pith = Path()
            let pr = orR * 0.20
            pith.addEllipse(in: CGRect(x: orCx - pr, y: orCy - pr, width: pr*2, height: pr*2))
            context.fill(pith, with: .color(.white.opacity(0.85)))

            // ── Sal de gusano: rounded conical mound, single color ────────────
            let salCx:  CGFloat = w * 0.875
            let salBaseY: CGFloat = h * 0.90   // sits on same baseline as glass
            let salRx:  CGFloat = w * 0.120    // half-width of base
            let salH:   CGFloat = h * 0.18     // height of mound
            let salColor = Color(red: 0.72, green: 0.42, blue: 0.22)

            // Mound as a triangle with rounded top (arc peak + straight sides to base)
            var mound = Path()
            mound.move(to: CGPoint(x: salCx - salRx, y: salBaseY))
            // Left side up to near peak
            mound.addLine(to: CGPoint(x: salCx - salRx * 0.25, y: salBaseY - salH * 0.82))
            // Rounded peak arc
            mound.addQuadCurve(
                to: CGPoint(x: salCx + salRx * 0.25, y: salBaseY - salH * 0.82),
                control: CGPoint(x: salCx, y: salBaseY - salH * 1.08)
            )
            // Right side back down
            mound.addLine(to: CGPoint(x: salCx + salRx, y: salBaseY))
            // Rounded base
            mound.addQuadCurve(
                to: CGPoint(x: salCx - salRx, y: salBaseY),
                control: CGPoint(x: salCx, y: salBaseY + h * 0.025)
            )
            mound.closeSubpath()
            context.fill(mound, with: .color(salColor))
            context.stroke(mound, with: .color(salColor.opacity(0.70)),
                           lineWidth: max(0.4, w * 0.018))
        }
        .frame(width: size, height: size)
    }
}

/// Custom flan icon drawn as a SwiftUI vector.
/// A round caramel custard on a small plate, with golden-brown
/// caramel dripping over a pale yellow custard body.
///
/// **Minimum safe size: 16pt.** Below that, Canvas geometry calculations can produce
/// NaN values that freeze CoreGraphics. Falls back to emoji at tiny sizes.
struct FlanIcon: View {
    var size: CGFloat = 28

    /// Below this threshold, Canvas geometry produces NaN values that crash CoreGraphics.
    private static let minimumCanvasSize: CGFloat = 14

    var body: some View {
        if size < Self.minimumCanvasSize {
            // Emoji fallback — avoids NaN from Canvas geometry at very small sizes
            Text("🍮")
                .font(.system(size: size * 0.75))
                .frame(width: size, height: size)
        } else {
            canvasIcon
        }
    }

    private var canvasIcon: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // -- Plate (thin oval at the bottom) --
            let plateRect = CGRect(
                x: w * 0.05,
                y: h * 0.78,
                width: w * 0.9,
                height: h * 0.18
            )
            let platePath = Path(ellipseIn: plateRect)
            context.fill(platePath, with: .color(Color(.systemGray4)))
            context.stroke(platePath, with: .color(Color(.systemGray3)), lineWidth: max(0.5, w * 0.02))

            // -- Custard body (trapezoid: wider at bottom, slightly narrower at top) --
            let custardBottom = h * 0.82
            let custardTop = h * 0.28
            let bottomLeft = w * 0.18
            let bottomRight = w * 0.82
            let topLeft = w * 0.25
            let topRight = w * 0.75

            var custardPath = Path()
            custardPath.move(to: CGPoint(x: topLeft, y: custardTop))
            custardPath.addLine(to: CGPoint(x: bottomLeft, y: custardBottom))
            // Rounded bottom
            custardPath.addQuadCurve(
                to: CGPoint(x: bottomRight, y: custardBottom),
                control: CGPoint(x: w * 0.5, y: custardBottom + h * 0.04)
            )
            custardPath.addLine(to: CGPoint(x: topRight, y: custardTop))
            // Flat top
            custardPath.addLine(to: CGPoint(x: topLeft, y: custardTop))
            custardPath.closeSubpath()

            // Pale yellow custard fill
            context.fill(custardPath, with: .color(Color(red: 0.98, green: 0.88, blue: 0.55)))

            // Custard outline
            context.stroke(custardPath, with: .color(Color(red: 0.85, green: 0.72, blue: 0.35).opacity(0.6)), lineWidth: max(0.5, w * 0.02))

            // -- Caramel top layer --
            let caramelY = custardTop
            let caramelDepth = h * 0.12

            var caramelPath = Path()
            caramelPath.move(to: CGPoint(x: topLeft, y: caramelY))
            // Top edge (slightly domed)
            caramelPath.addQuadCurve(
                to: CGPoint(x: topRight, y: caramelY),
                control: CGPoint(x: w * 0.5, y: caramelY - h * 0.04)
            )
            // Bottom edge with drip effect
            caramelPath.addQuadCurve(
                to: CGPoint(x: w * 0.58, y: caramelY + caramelDepth * 1.4),
                control: CGPoint(x: topRight - w * 0.02, y: caramelY + caramelDepth * 0.5)
            )
            // Drip going further down on right side
            caramelPath.addQuadCurve(
                to: CGPoint(x: w * 0.45, y: caramelY + caramelDepth),
                control: CGPoint(x: w * 0.52, y: caramelY + caramelDepth * 1.5)
            )
            caramelPath.addQuadCurve(
                to: CGPoint(x: topLeft, y: caramelY),
                control: CGPoint(x: topLeft + w * 0.02, y: caramelY + caramelDepth * 0.3)
            )
            caramelPath.closeSubpath()

            // Rich amber/brown caramel
            context.fill(caramelPath, with: .color(Color(red: 0.78, green: 0.45, blue: 0.10)))

            // Caramel highlight
            var highlightPath = Path()
            let hlX = w * 0.35
            let hlY = caramelY + h * 0.01
            highlightPath.addEllipse(in: CGRect(x: hlX, y: hlY, width: w * 0.2, height: h * 0.04))
            context.fill(highlightPath, with: .color(Color(red: 0.90, green: 0.58, blue: 0.18).opacity(0.5)))

        }
        .frame(width: size, height: size)
    }
}

/// Convenience view that shows the right icon for any SpotCategory.
/// Flan and Mezcal use custom SwiftUI drawings.
/// Trending Flezcals show the 🐛 worm emoji.
/// Any new category automatically gets its emoji as a fallback — no changes needed here.
struct CategoryIcon: View {
    let category: SpotCategory
    var size: CGFloat = 28

    var body: some View {
        switch category {
        case .flan:
            FlanIcon(size: size)
        case .mezcal:
            VeladoraIcon(size: size)
        default:
            // All other categories (including custom): render the emoji at a proportional size
            // Custom Flezcals use 🐛 worm emoji (via SpotCategory.emoji)
            Text(category.emoji)
                .font(.system(size: size * 0.75))
                .frame(width: size, height: size)
        }
    }
}

/// Convenience view that shows the right icon for any FoodCategory.
/// Delegates to CategoryIcon via SpotCategory for unified rendering.
struct FoodCategoryIcon: View {
    let category: FoodCategory
    var size: CGFloat = 28

    var body: some View {
        CategoryIcon(category: SpotCategory(rawValue: category.id), size: size)
    }
}

/// Shows category icons for a spot, scaling gracefully from 1 to many categories.
///
/// Designed to fit inside a container ~1.6× the `size` parameter (e.g. size 28 in
/// a 44pt frame, or size 22 in a 40pt circle).
///
/// Layout by count:
/// - **1 category**: single icon at full size
/// - **2 categories**: side-by-side at 70% size
/// - **3 categories**: side-by-side at 50% size
/// - **4+ categories**: first 2 icons at 55% size plus a "+N" overflow badge
struct SpotIcons: View {
    let categories: [SpotCategory]
    var size: CGFloat = 28

    var body: some View {
        switch categories.count {
        case 0:
            CategoryIcon(category: .flan, size: size)
        case 1:
            CategoryIcon(category: categories[0], size: size)
        case 2:
            HStack(spacing: size * 0.08) {
                ForEach(categories) { cat in
                    CategoryIcon(category: cat, size: size * 0.7)
                }
            }
        case 3:
            // 3 icons at 50% — fits within 1.6× container
            HStack(spacing: size * 0.04) {
                ForEach(categories) { cat in
                    CategoryIcon(category: cat, size: size * 0.50)
                }
            }
        default:
            // 4+ categories: show first 2 icons + "+N" badge
            let visible = Array(categories.prefix(2))
            let overflow = categories.count - 2

            HStack(spacing: size * 0.04) {
                ForEach(visible) { cat in
                    CategoryIcon(category: cat, size: size * 0.50)
                }
                Text("+\(overflow)")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
    }
}

#Preview("Icon Gallery") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            VStack {
                FlanIcon(size: 16)
                Text("16pt").font(.caption2)
            }
            VStack {
                FlanIcon(size: 28)
                Text("28pt").font(.caption2)
            }
            VStack {
                FlanIcon(size: 44)
                Text("44pt").font(.caption2)
            }
            VStack {
                FlanIcon(size: 64)
                Text("64pt").font(.caption2)
            }
        }

        Divider()

        HStack(spacing: 20) {
            VStack {
                VeladoraIcon(size: 16)
                Text("16pt").font(.caption2)
            }
            VStack {
                VeladoraIcon(size: 28)
                Text("28pt").font(.caption2)
            }
            VStack {
                VeladoraIcon(size: 44)
                Text("44pt").font(.caption2)
            }
            VStack {
                VeladoraIcon(size: 64)
                Text("64pt").font(.caption2)
            }
        }

        Divider()

        HStack(spacing: 20) {
            VStack {
                SpotIcons(categories: [.flan], size: 44)
                    .frame(width: 56, height: 56)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("1 pick").font(.caption)
            }
            VStack {
                SpotIcons(categories: [.flan, .mezcal], size: 44)
                    .frame(width: 56, height: 56)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("2 picks").font(.caption)
            }
            VStack {
                SpotIcons(categories: [.flan, .mezcal, .tacos], size: 44)
                    .frame(width: 56, height: 56)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("3 picks").font(.caption)
            }
            VStack {
                SpotIcons(categories: [.flan, .mezcal, .tacos, .ramen, .birria], size: 44)
                    .frame(width: 56, height: 56)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("5 picks").font(.caption)
            }
        }
    }
    .padding()
}
