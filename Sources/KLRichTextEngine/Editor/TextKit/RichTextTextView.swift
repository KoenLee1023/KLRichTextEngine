#if os(iOS)
import UIKit

final class RichTextTextView: UITextView {
    var traitsDidChange: (() -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self,
            UITraitUserInterfaceStyle.self,
        ]) { (view: RichTextTextView, _: UITraitCollection) in
            view.traitsDidChange?()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self,
            UITraitUserInterfaceStyle.self,
        ]) { (view: RichTextTextView, _: UITraitCollection) in
            view.traitsDidChange?()
        }
    }

    override var intrinsicContentSize: CGSize {
        guard !isScrollEnabled else { return super.intrinsicContentSize }
        return sizeThatFits(
            CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        )
    }
}

extension NSRange {
    func clamped(toUTF16Length length: Int) -> NSRange {
        let location = min(max(0, location), length)
        let available = length - location
        return NSRange(location: location, length: min(max(0, self.length), available))
    }
}
#endif
