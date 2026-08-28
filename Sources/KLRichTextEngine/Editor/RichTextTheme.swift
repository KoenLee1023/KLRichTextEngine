#if os(iOS)
import SwiftUI

@MainActor
/// Colors, fonts, and spacing used by the package views.
public struct RichTextTheme {
    public var accentColor: Color
    public var checkedColor: Color
    public var defaultTextColor: Color

    public init(
        accentColor: Color = .accentColor,
        checkedColor: Color = .secondary,
        defaultTextColor: Color = .primary
    ) {
        self.accentColor = accentColor
        self.checkedColor = checkedColor
        self.defaultTextColor = defaultTextColor
    }

    public static var standard: Self { Self() }
}
#endif
