import Foundation

public struct RichTextSelection: Equatable, Sendable {
    public var locationUTF16: Int
    public var lengthUTF16: Int

    public init(locationUTF16: Int, lengthUTF16: Int) {
        self.locationUTF16 = locationUTF16
        self.lengthUTF16 = lengthUTF16
    }
}
