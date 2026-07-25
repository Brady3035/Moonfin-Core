import UIKit

final class SubtitleOverlay: UIView {

    private let textLabel = UILabel()
    private let bitmapView = UIImageView()
    private let assImageView = UIImageView()
    private var eventQueue: [SubtitleEvent] = []
    private var activeEvent: SubtitleEvent?
    private var lastUpdateTime: TimeInterval = 0
    var delaySeconds: TimeInterval = 0

    private var subtitleFontSize: CGFloat = 24
    private var subtitleFontWeight: UIFont.Weight = .semibold
    private var subtitleTextColor: UIColor = .white
    private var subtitleBgColor: UIColor = .clear
    private var subtitleStrokeColor: UIColor = .black
    private var subtitleStrokeWidth: CGFloat = 2
    private var subtitleBottomOffset: CGFloat = 80

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.isHidden = true
        addSubview(textLabel)

        bitmapView.contentMode = .scaleToFill
        bitmapView.isHidden = true
        addSubview(bitmapView)

        assImageView.contentMode = .scaleToFill
        assImageView.isHidden = true
        addSubview(assImageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTextLabel()
        layoutBitmapView()
        assImageView.frame = bounds
    }

    func showAssImage(_ image: CGImage?) {
        if let image {
            assImageView.image = UIImage(cgImage: image)
            assImageView.isHidden = false
        } else {
            assImageView.image = nil
            assImageView.isHidden = true
        }
    }

    /// The engine republishes the full active-cue set, so replace the queue
    /// wholesale and re-evaluate at the last known clock so a cue swap shows
    /// without waiting for the next tick.
    func setEvents(_ events: [SubtitleEvent]) {
        eventQueue = events.sorted { $0.startTime < $1.startTime }
        if lastUpdateTime > 0 {
            evaluate(at: lastUpdateTime, evict: false)
        } else if events.isEmpty, activeEvent != nil {
            hideAll()
        }
    }

    func update(currentTime: TimeInterval) {
        lastUpdateTime = currentTime
        evaluate(at: currentTime, evict: true)
    }

    private func evaluate(at currentTime: TimeInterval, evict: Bool) {
        let adjusted = currentTime - delaySeconds
        if evict {
            eventQueue.removeAll { $0.endTime < adjusted - 0.5 }
        }
        let current = eventQueue.first { adjusted >= $0.startTime && adjusted < $0.endTime }

        if let current {
            if activeEvent == nil || activeEvent!.startTime != current.startTime {
                showEvent(current)
            }
        } else if activeEvent != nil {
            hideAll()
        }
    }

    func clear() {
        eventQueue.removeAll()
        lastUpdateTime = 0
        hideAll()
        assImageView.image = nil
        assImageView.isHidden = true
    }

    /// Moonfin's typed subtitle-style contract, mirroring the Dart
    /// `configureSubtitleStyle` call. Colors are ARGB ints, `fontSize` is the
    /// user-facing size on the 24-based scale, and `verticalOffset` from 0 to
    /// 1 maps to a bottom margin.
    func applyStyle(
        textColor: Int?,
        backgroundColor: Int?,
        strokeColor: Int?,
        fontSize: Double?,
        fontWeight: Int?,
        verticalOffset: Double?
    ) {
        if let textColor { subtitleTextColor = Self.colorFromARGB(textColor) }
        if let backgroundColor { subtitleBgColor = Self.colorFromARGB(backgroundColor) }
        if let strokeColor {
            subtitleStrokeColor = Self.colorFromARGB(strokeColor)
            subtitleStrokeWidth = Self.colorFromARGB(strokeColor) == .clear ? 0 : 2
        }
        if let fontSize, fontSize > 0 {
            // Scale the 24-based user size up to the TV canvas, clamped.
            subtitleFontSize = CGFloat(min(max(fontSize / 24.0 * 55.0, 24), 120))
        }
        if let fontWeight {
            subtitleFontWeight = fontWeight >= 600 ? .bold : .semibold
        }
        if let verticalOffset {
            setSubtitlePosition(basePosition: 100 - Int((verticalOffset * 60).rounded()))
        }
        if let event = activeEvent, event.text != nil {
            showEvent(event)
        }
    }

    /// Subtitle position on a 40 to 100 scale, where 100 is the bottom edge,
    /// converted to a bottom offset in points. The OSD raise path calls this
    /// with min(base, 70) while controls are up.
    func setSubtitlePosition(basePosition: Int) {
        let pos = min(max(basePosition, 40), 100)
        let travel = (bounds.height > 0 ? bounds.height : 1080) * 0.5
        subtitleBottomOffset = 40 + travel * CGFloat(100 - pos) / 60.0
        setNeedsLayout()
    }

    // MARK: - Display

    private func showEvent(_ event: SubtitleEvent) {
        activeEvent = event
        if let text = event.text {
            bitmapView.isHidden = true
            bitmapView.image = nil
            textLabel.attributedText = styledText(text)
            textLabel.isHidden = false
            layoutTextLabel()
        } else if let bitmap = event.bitmap {
            textLabel.isHidden = true
            textLabel.attributedText = nil
            bitmapView.image = UIImage(cgImage: bitmap)
            bitmapView.isHidden = false
            layoutBitmapView()
        }
    }

    private func hideAll() {
        activeEvent = nil
        textLabel.isHidden = true
        textLabel.attributedText = nil
        bitmapView.isHidden = true
        bitmapView.image = nil
    }

    private func layoutTextLabel() {
        guard !textLabel.isHidden else { return }
        let maxWidth = bounds.width * 0.9
        let size = textLabel.sizeThatFits(CGSize(width: maxWidth, height: bounds.height * 0.4))
        textLabel.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - size.height - subtitleBottomOffset,
            width: size.width,
            height: size.height
        )
    }

    private func layoutBitmapView() {
        guard !bitmapView.isHidden, let event = activeEvent else { return }
        if let rect = event.normalizedRect, let canvas = event.canvasSize,
            canvas.width > 0, canvas.height > 0
        {
            // Map the authored composition canvas onto the view width-aligned
            // and center-anchored (the canvas may be taller than the coded
            // video for cropped rips), then place the cue inside it.
            let scale = bounds.width / canvas.width
            let canvasHeight = canvas.height * scale
            let yOrigin = (bounds.height - canvasHeight) / 2
            bitmapView.frame = CGRect(
                x: rect.origin.x * bounds.width,
                y: yOrigin + rect.origin.y * canvasHeight,
                width: rect.size.width * bounds.width,
                height: rect.size.height * canvasHeight
            )
        } else if event.bitmapWidth > 0 {
            let scale = min(bounds.width / CGFloat(event.bitmapWidth), 1.0)
            let w = CGFloat(event.bitmapWidth) * scale
            let h = CGFloat(event.bitmapHeight) * scale
            bitmapView.frame = CGRect(
                x: (bounds.width - w) / 2,
                y: bounds.height - h - subtitleBottomOffset,
                width: w,
                height: h
            )
        }
    }

    private func styledText(_ text: String) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: subtitleFontSize, weight: subtitleFontWeight)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: subtitleTextColor,
        ]
        if subtitleStrokeWidth > 0 {
            attrs[.strokeColor] = subtitleStrokeColor
            attrs[.strokeWidth] = -subtitleStrokeWidth
        }
        if subtitleBgColor != .clear {
            attrs[.backgroundColor] = subtitleBgColor
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private static func colorFromARGB(_ argb: Int) -> UIColor {
        let alpha = (argb >> 24) & 0xFF
        if alpha == 0 { return .clear }
        return UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255.0,
            green: CGFloat((argb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(argb & 0xFF) / 255.0,
            alpha: CGFloat(alpha) / 255.0
        )
    }

}
