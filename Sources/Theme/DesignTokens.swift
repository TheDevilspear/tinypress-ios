import SwiftUI
import UIKit

enum DesignTokens {
    enum Colors {
        // Adaptive dark-room surfaces: deep neutral charcoal in dark mode, crisp studio paper in light mode.
        static let background = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1.0)
                : UIColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1.0)
        })

        static let secondarySurface = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.086, green: 0.094, blue: 0.110, alpha: 1.0)
                : UIColor.white
        })

        static let tertiarySurface = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.125, green: 0.137, blue: 0.161, alpha: 1.0)
                : UIColor(red: 0.933, green: 0.937, blue: 0.953, alpha: 1.0)
        })

        static let viewportSurface = Color(red: 0.024, green: 0.027, blue: 0.031)

        static let cardBorder = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.09)
                : UIColor.black.withAlphaComponent(0.07)
        })

        static let glassTint = Color.black.opacity(0.46)
        static let glassStroke = Color.white.opacity(0.22)
        static let overlayBadge = Color.black.opacity(0.68)

        static let accent = Color.accentColor
        static let success = Color(uiColor: .systemGreen)
        static let warning = Color(uiColor: .systemOrange)
        static let danger = Color(uiColor: .systemRed)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let divider = Color(uiColor: .separator)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
        static let pill: CGFloat = 999
    }

    enum TouchTarget {
        static let minimum: CGFloat = 44
        static let buttonHeight: CGFloat = 50
    }

    enum Typography {
        static let title = Font.title2.weight(.bold)
        static let largeMetric = Font.title2.weight(.bold).monospacedDigit()
        static let headline = Font.headline.weight(.semibold)
        static let body = Font.body
        static let caption = Font.caption.weight(.medium)
        static let badge = Font.caption2.weight(.bold).monospacedDigit()
        static let monoMetric = Font.subheadline.weight(.semibold).monospacedDigit()
    }

    enum Motion {
        static let snappySpring = Animation.spring(response: 0.28, dampingFraction: 0.82)
        static let gentleSpring = Animation.spring(response: 0.36, dampingFraction: 0.86)
    }

    @MainActor
    enum Haptics {
        static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }

        static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }
    }
}
