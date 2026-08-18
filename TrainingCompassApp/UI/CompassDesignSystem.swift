import SwiftUI
import UIKit

/// The visual language shared by every Training Compass surface.
///
/// The pinned four-phone reference is the visual authority: a compact white
/// working surface, editorial orientation type, dense operational typography,
/// fine rules, blue actions, and green evidence states.
enum CompassPalette {
    static let paper = Color(uiColor: paperUIColor)
    static let surface = Color(uiColor: surfaceUIColor)
    static let navy = Color(uiColor: navyUIColor)
    static let blue = Color(uiColor: blueUIColor)
    static let green = Color(uiColor: greenUIColor)
    static let red = Color(uiColor: redUIColor)
    static let inkMuted = Color(uiColor: inkMutedUIColor)
    static let line = Color(uiColor: lineUIColor)

    static let paperUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.09, blue: 0.12, alpha: 1)
            : UIColor(red: 0.965, green: 0.969, blue: 0.972, alpha: 1)
    }

    static let surfaceUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
            : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    }

    static let navyUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.91, green: 0.93, blue: 0.97, alpha: 1)
            : UIColor(red: 0.035, green: 0.075, blue: 0.13, alpha: 1)
    }

    static let blueUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.67, blue: 1, alpha: 1)
            : UIColor(red: 0.015, green: 0.35, blue: 0.74, alpha: 1)
    }

    static let greenUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.32, green: 0.82, blue: 0.49, alpha: 1)
            : UIColor(red: 0.0, green: 0.52, blue: 0.24, alpha: 1)
    }

    static let redUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.43, blue: 0.46, alpha: 1)
            : UIColor(red: 0.76, green: 0.10, blue: 0.16, alpha: 1)
    }

    static let inkMutedUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.68, green: 0.71, blue: 0.76, alpha: 1)
            : UIColor(red: 0.32, green: 0.34, blue: 0.37, alpha: 1)
    }

    static let lineUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.22, green: 0.25, blue: 0.30, alpha: 1)
            : UIColor(red: 0.86, green: 0.87, blue: 0.88, alpha: 1)
    }
}

struct CompassPaperBackground: View {
    var body: some View {
        CompassPalette.paper
            .allowsHitTesting(false)
    }
}

struct CompassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CompassPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.07), radius: 4, x: 0, y: 2)
    }
}

struct CompassSectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(CompassPalette.navy)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(CompassPalette.inkMuted)
            }
        }
    }
}

struct CompassStatusPill: View {
    let title: String
    var color: Color = CompassPalette.blue

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
    }
}

struct CompassRoundSymbol: View {
    let systemImage: String
    var color: Color = CompassPalette.blue

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

struct CompassMetricValue: View {
    let label: String
    let value: String
    var detail: String?
    var detailColor: Color = CompassPalette.green

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(CompassPalette.inkMuted)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(CompassPalette.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(detailColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompassTopBarTitleModifier: ViewModifier {
    let title: String
    let subtitle: String?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title, design: .serif).weight(.bold))
                    .foregroundStyle(CompassPalette.navy)
                    .tracking(-0.5)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CompassPalette.inkMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.trailing, 72)
            .padding(.top, 2)
            .padding(.bottom, 8)
            .background(CompassPalette.paper)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The product mark shared by the app icon and branded orientation moments.
///
/// Drawing the compact in-app version keeps it crisp at every display scale
/// while preserving the geometry of the supplied reference.
struct CompassBrandMark: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side * 0.43
            let lineWidth = max(1.25, side * 0.038)

            let ring = Path(
                ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2,
                ),
            )
            context.stroke(ring, with: .color(CompassPalette.navy), lineWidth: lineWidth)

            for degrees in stride(from: 0.0, to: 360.0, by: 45.0) {
                let angle = degrees * .pi / 180
                let isCardinal = degrees.truncatingRemainder(dividingBy: 90) == 0
                let outerRadius = radius - lineWidth * 0.45
                let innerRadius = radius - side * (isCardinal ? 0.12 : 0.085)
                var tick = Path()
                tick.move(to: point(from: center, angle: angle, distance: innerRadius))
                tick.addLine(to: point(from: center, angle: angle, distance: outerRadius))
                context.stroke(
                    tick,
                    with: .color(isCardinal ? CompassPalette.navy : CompassPalette.line),
                    style: StrokeStyle(lineWidth: max(1, lineWidth * 0.72), lineCap: .round),
                )
            }

            let needleAngle = -Double.pi / 4
            let perpendicular = needleAngle + Double.pi / 2
            let tipDistance = side * 0.31
            let halfWidth = side * 0.105
            let northTip = point(from: center, angle: needleAngle, distance: tipDistance)
            let southTip = point(from: center, angle: needleAngle + .pi, distance: tipDistance)
            let left = point(from: center, angle: perpendicular, distance: halfWidth)
            let right = point(from: center, angle: perpendicular + .pi, distance: halfWidth)

            var northNeedle = Path()
            northNeedle.move(to: center)
            northNeedle.addLine(to: left)
            northNeedle.addLine(to: northTip)
            northNeedle.addLine(to: center)
            context.fill(northNeedle, with: .color(CompassPalette.blue.opacity(0.48)))
            context.stroke(northNeedle, with: .color(CompassPalette.navy), lineWidth: lineWidth * 0.7)

            var southNeedle = Path()
            southNeedle.move(to: center)
            southNeedle.addLine(to: right)
            southNeedle.addLine(to: southTip)
            southNeedle.addLine(to: center)
            context.fill(southNeedle, with: .color(CompassPalette.blue))
            context.stroke(southNeedle, with: .color(CompassPalette.navy), lineWidth: lineWidth * 0.7)

            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - lineWidth,
                        y: center.y - lineWidth,
                        width: lineWidth * 2,
                        height: lineWidth * 2,
                    ),
                ),
                with: .color(CompassPalette.navy),
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func point(from origin: CGPoint, angle: Double, distance: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(cos(angle)) * distance,
            y: origin.y + CGFloat(sin(angle)) * distance,
        )
    }
}

struct CompassPageHeader: View {
    let title: String?
    let subtitle: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(.system(.title, design: .serif).weight(.bold))
                        .foregroundStyle(CompassPalette.navy)
                        .tracking(-0.35)
                }
                if let subtitle {
                    Text(subtitle)
                        // The date is orientation metadata, so keep it subordinate to the
                        // native page title even when Dynamic Type is very large.
                        .font(
                            dynamicTypeSize.isAccessibilitySize
                                ? .footnote.weight(.medium)
                                : .subheadline.weight(.medium),
                        )
                        .foregroundStyle(CompassPalette.inkMuted)
                }
            }
        }
        // Keep the orientation treatment legible without letting an extreme
        // accessibility size push the work surface below the tab bar.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

struct CompassEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(CompassPalette.blue)
                .frame(width: 72, height: 72)
                .background(CompassPalette.blue.opacity(0.10), in: Circle())
            Text(title)
                .font(
                    .system(
                        dynamicTypeSize.isAccessibilitySize ? .subheadline : .title3,
                        design: .serif,
                    ).weight(.bold),
                )
                .foregroundStyle(CompassPalette.navy)
                .multilineTextAlignment(.center)
            Text(message)
                .font(dynamicTypeSize.isAccessibilitySize ? .footnote : .body)
                .foregroundStyle(CompassPalette.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(CompassPalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: Color.black.opacity(0.075), radius: 6, x: 0, y: 2)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

struct CompassScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(CompassPalette.blue)
            .background(CompassPaperBackground().ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .listSectionSpacing(10)
            .contentMargins(.top, 4, for: .scrollContent)
            .contentMargins(.bottom, 112, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 42)
            .headerProminence(.increased)
            .toolbarBackground(CompassPalette.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(CompassPalette.paper, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

extension View {
    func compassScreen() -> some View {
        modifier(CompassScreenModifier())
    }

    func compassNavigationTitle(_: String) -> some View {
        self
    }

    func compassTopBarTitle(_ title: String, subtitle: String? = nil) -> some View {
        modifier(CompassTopBarTitleModifier(title: title, subtitle: subtitle))
    }
}

enum CompassAppearance {
    @MainActor
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = CompassPalette.paperUIColor
        nav.shadowColor = .clear
        let inlineDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
            .withDesign(.serif)?
            .withSymbolicTraits(.traitBold)
        let largeDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
            .withDesign(.serif)?
            .withSymbolicTraits(.traitBold)
        let inlineTitleFont = inlineDescriptor.map { UIFont(descriptor: $0, size: 0) }
            ?? .preferredFont(forTextStyle: .headline)
        let largeTitleFont = largeDescriptor.map { UIFont(descriptor: $0, size: 0) }
            ?? .preferredFont(forTextStyle: .largeTitle)
        nav.titleTextAttributes = [
            .font: inlineTitleFont,
            .foregroundColor: CompassPalette.navyUIColor,
        ]
        nav.largeTitleTextAttributes = [
            .font: largeTitleFont,
            .foregroundColor: CompassPalette.navyUIColor,
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = CompassPalette.blueUIColor

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = CompassPalette.paperUIColor
        tab.shadowColor = CompassPalette.lineUIColor
        UITabBar.appearance().standardAppearance = tab
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tab
        }
        UITabBar.appearance().tintColor = CompassPalette.blueUIColor

        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = CompassPalette.surfaceUIColor
    }
}
