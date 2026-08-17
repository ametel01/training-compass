import SwiftUI
import UIKit

/// The visual language shared by every Training Compass surface.
///
/// It deliberately stays on top of native SwiftUI controls: the app remains
/// recognisably iOS while carrying the supplied compass, paper, and editorial
/// reference system into every state.
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
      : UIColor(red: 0.973, green: 0.969, blue: 0.949, alpha: 1)
  }
  static let surfaceUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
      : UIColor(red: 1, green: 1, blue: 0.99, alpha: 0.96)
  }
  static let navyUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.91, green: 0.93, blue: 0.97, alpha: 1)
      : UIColor(red: 0.035, green: 0.11, blue: 0.20, alpha: 1)
  }
  static let blueUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.40, green: 0.67, blue: 1, alpha: 1)
      : UIColor(red: 0.025, green: 0.33, blue: 0.78, alpha: 1)
  }
  static let greenUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.32, green: 0.82, blue: 0.49, alpha: 1)
      : UIColor(red: 0.02, green: 0.50, blue: 0.23, alpha: 1)
  }
  static let redUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 1, green: 0.43, blue: 0.46, alpha: 1)
      : UIColor(red: 0.76, green: 0.10, blue: 0.16, alpha: 1)
  }
  static let inkMutedUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.68, green: 0.71, blue: 0.76, alpha: 1)
      : UIColor(red: 0.28, green: 0.31, blue: 0.36, alpha: 1)
  }
  static let lineUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.22, green: 0.25, blue: 0.30, alpha: 1)
      : UIColor(red: 0.88, green: 0.87, blue: 0.83, alpha: 1)
  }
}

struct CompassPaperBackground: View {
  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(CompassPalette.paper))

      // A restrained contour field keeps the reference's topographic character
      // without competing with content or reducing contrast.
      let origin = CGPoint(x: size.width * 0.78, y: -size.height * 0.03)
      for index in 0..<11 {
        let inset = CGFloat(index) * 18
        var path = Path()
        path.move(to: CGPoint(x: origin.x - 120 - inset, y: origin.y + 12 + inset))
        path.addCurve(
          to: CGPoint(x: size.width + 36, y: origin.y + 80 + inset),
          control1: CGPoint(x: origin.x - 36 - inset, y: origin.y - 26 + inset),
          control2: CGPoint(x: size.width - 20, y: origin.y + 6 + inset))
        path.addCurve(
          to: CGPoint(x: size.width - 4, y: origin.y + 176 + inset),
          control1: CGPoint(x: size.width + 40, y: origin.y + 114 + inset),
          control2: CGPoint(x: size.width - 40, y: origin.y + 152 + inset))
        context.stroke(path, with: .color(CompassPalette.line.opacity(0.44)), lineWidth: 0.7)
      }
    }
    .allowsHitTesting(false)
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
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        Circle()
          .fill(CompassPalette.surface)
          .overlay(Circle().stroke(CompassPalette.line, lineWidth: 1))
        Image(systemName: "location.north.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(CompassPalette.blue)
          .rotationEffect(.degrees(24))
      }
      .frame(width: 42, height: 42)

      VStack(alignment: .leading, spacing: 2) {
        if let title {
          Text(title)
            .font(.system(.largeTitle, design: .serif).weight(.bold))
            .foregroundStyle(CompassPalette.navy)
            .tracking(-0.5)
        }
        if let subtitle {
          Text(subtitle)
            // The date is orientation metadata, so keep it subordinate to the
            // native page title even when Dynamic Type is very large.
            .font(
              dynamicTypeSize.isAccessibilitySize
                ? .footnote.weight(.medium)
                : .subheadline.weight(.medium)
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
            design: .serif
          ).weight(.bold)
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
    .padding(.vertical, 42)
    .background(CompassPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(CompassPalette.line.opacity(0.9), lineWidth: 1)
    )
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
  }
}

struct CompassScreenModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .tint(CompassPalette.blue)
      .background(CompassPaperBackground().ignoresSafeArea())
      .scrollContentBackground(.hidden)
      .listStyle(.grouped)
      .environment(\.defaultMinListRowHeight, 46)
      .headerProminence(.standard)
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
}

enum CompassAppearance {
  @MainActor
  static func apply() {
    let nav = UINavigationBarAppearance()
    nav.configureWithOpaqueBackground()
    nav.backgroundColor = CompassPalette.paperUIColor
    nav.shadowColor = CompassPalette.lineUIColor
    // Keep title sizing and color native so Dynamic Type and accessibility text
    // sizes continue to scale and adapt with the navigation system.
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
  }
}
