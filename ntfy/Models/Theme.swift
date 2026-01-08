import SwiftUI

struct AppColors {
    // Primary colors
    static let primary = Color("AccentColor")
    static let secondary = Color.secondary

    // Background colors
    static let background = Color(uiColor: .systemBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    // Priority colors
    static let priorityMin = Color.gray
    static let priorityLow = Color.blue
    static let priorityDefault = Color.primary
    static let priorityHigh = Color.orange
    static let priorityUrgent = Color.red

    // Semantic colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    static func priority(_ level: Priority) -> Color {
        switch level {
        case .min: return priorityMin
        case .low: return priorityLow
        case .default: return priorityDefault
        case .high: return priorityHigh
        case .urgent: return priorityUrgent
        }
    }
}

struct AppFonts {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title.weight(.semibold)
    static let title2 = Font.title2.weight(.semibold)
    static let title3 = Font.title3.weight(.medium)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let caption2 = Font.caption2

    static let monospacedBody = Font.system(.body, design: .monospaced)
    static let monospacedCaption = Font.system(.caption, design: .monospaced)
}

struct AppSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

struct AppCornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.primary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.headline)
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - SF Symbol Icons

struct AppIcons {
    // Navigation
    static let topics = "list.bullet"
    static let messages = "bubble.left.and.bubble.right"
    static let settings = "gear"
    static let add = "plus"
    static let close = "xmark"
    static let back = "chevron.left"
    static let forward = "chevron.right"

    // Actions
    static let send = "paperplane.fill"
    static let delete = "trash"
    static let edit = "pencil"
    static let copy = "doc.on.doc"
    static let share = "square.and.arrow.up"
    static let refresh = "arrow.clockwise"
    static let mute = "bell.slash"
    static let unmute = "bell"

    // Status
    static let unread = "circle.fill"
    static let read = "circle"
    static let attachment = "paperclip"
    static let link = "link"

    // Priority
    static let priorityMin = "arrow.down.to.line"
    static let priorityLow = "arrow.down"
    static let priorityDefault = "minus"
    static let priorityHigh = "arrow.up"
    static let priorityUrgent = "exclamationmark.2"

    // Misc
    static let server = "server.rack"
    static let notification = "bell.badge"
    static let theme = "paintbrush"
    static let info = "info.circle"
    static let checkmark = "checkmark"
    static let error = "exclamationmark.triangle"
    static let empty = "tray"
}
