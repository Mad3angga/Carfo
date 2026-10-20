import AppKit
import SwiftUI

enum CarfoDesign {
    private static func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        }
    }
    static let secondaryNSColor = adaptive((94/255, 101/255, 114/255), (184/255, 193/255, 206/255))
    static let secondary = Color(nsColor: secondaryNSColor)
    static let accent = Color(nsColor: adaptive((7/255, 90/255, 184/255), (121/255, 184/255, 255/255)))
    static let action = Color(nsColor: adaptive((8/255, 102/255, 216/255), (22/255, 105/255, 204/255)))
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "Inter", size: size) != nil { return .custom("Inter", size: size).weight(weight) }
        return .system(size: size, weight: weight)
    }
}

typealias FootageDesign = CarfoDesign

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

struct GlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background {
                if scheme == .dark {
                    ZStack {
                        VisualEffect(material: .popover)
                        Color(red: 0.12, green: 0.135, blue: 0.16).opacity(0.96)
                    }
                } else {
                    Color.white
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        scheme == .dark
                            ? Color.white.opacity(0.18)
                            : Color(red: 0.88, green: 0.90, blue: 0.93),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.3 : 0.08),
                radius: scheme == .dark ? 14 : 10,
                y: scheme == .dark ? 6 : 4
            )
    }
}

struct Keycap: View {
    var text: String
    var body: some View {
        Text(text).font(CarfoDesign.font(10)).foregroundStyle(CarfoDesign.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.22), lineWidth: 0.6))
    }
}

struct StateMessage: View {
    let symbol: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(CarfoDesign.secondary)
            Text(title).font(CarfoDesign.font(13, weight: .semibold))
            Text(detail).font(CarfoDesign.font(11)).foregroundStyle(CarfoDesign.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(.small).tint(CarfoDesign.action).padding(.top, 2)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}

struct KeycapBadge: View {
    var text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(CarfoDesign.font(11.5, weight: .medium))
            .foregroundStyle(scheme == .dark ? Color.white : Color(red: 0.15, green: 0.17, blue: 0.20))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.12) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(scheme == .dark ? Color.white.opacity(0.18) : Color(red: 0.82, green: 0.85, blue: 0.89), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.04), radius: 1, y: 1)
    }
}

struct CustomThemePicker: View {
    @ObservedObject var model: AppModel
    var showsBlueBorder: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool {
        switch model.appearance {
        case .dark: return true
        case .light: return false
        case .system: return scheme == .dark
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppAppearance.allCases) { option in
                let selected = model.appearance == option
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        model.appearance = option
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        Text(option.title)
                            .font(CarfoDesign.font(11.5, weight: selected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isDark ? Color(red: 0.22, green: 0.24, blue: 0.28) : Color.white)
                                .shadow(color: .black.opacity(isDark ? 0.3 : 0.06), radius: 2, y: 1)
                        }
                    }
                    .overlay {
                        if selected {
                            if showsBlueBorder && !isDark {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(CarfoDesign.action, lineWidth: 1.2)
                            } else if !isDark {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color(red: 0.85, green: 0.87, blue: 0.90), lineWidth: 0.8)
                            }
                        }
                    }
                    .foregroundStyle(
                        selected
                            ? (showsBlueBorder && !isDark ? CarfoDesign.action : (isDark ? .white : Color.primary))
                            : (isDark ? Color(red: 0.65, green: 0.68, blue: 0.74) : Color(red: 0.32, green: 0.36, blue: 0.42))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.08) : Color(red: 0.92, green: 0.93, blue: 0.95))
        )
    }
}

typealias ThemePicker = CustomThemePicker

