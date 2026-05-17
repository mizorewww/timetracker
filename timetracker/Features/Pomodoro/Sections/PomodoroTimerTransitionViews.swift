import QuartzCore
import SwiftUI

enum PomodoroTimerFaceSource: Hashable {
    case setup
    case active
}

struct PomodoroTimerFaceContent {
    let timeText: String
    let title: String
    let titleColor: Color
}

struct PomodoroTimerFaceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [PomodoroTimerFaceSource: CGRect] = [:]

    static func reduce(
        value: inout [PomodoroTimerFaceSource: CGRect],
        nextValue: () -> [PomodoroTimerFaceSource: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func pomodoroTimerFaceSource(_ source: PomodoroTimerFaceSource) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PomodoroTimerFaceFramePreferenceKey.self,
                    value: [source: proxy.frame(in: .named(PomodoroStyle.timerCoordinateSpace))]
                )
            }
        }
    }
}

#if os(iOS)
struct PomodoroHighRefreshTimerFace: UIViewRepresentable {
    let content: PomodoroTimerFaceContent
    let frame: CGRect?

    func makeUIView(context: Context) -> PomodoroTimerFaceContainerView {
        PomodoroTimerFaceContainerView()
    }

    func updateUIView(_ view: PomodoroTimerFaceContainerView, context: Context) {
        view.update(content: content, targetFrame: frame)
    }
}

final class PomodoroTimerFaceContainerView: UIView {
    private let faceView = PomodoroTimerFaceUIView()
    private var lastFrame: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        faceView.layer.allowsEdgeAntialiasing = true
        addSubview(faceView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(content: PomodoroTimerFaceContent, targetFrame: CGRect?) {
        faceView.update(content: content)
        guard let targetFrame else {
            faceView.isHidden = true
            return
        }

        faceView.isHidden = false
        let targetBounds = CGRect(origin: .zero, size: targetFrame.size)
        let targetPosition = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let currentPosition = faceView.layer.presentation()?.position ?? faceView.layer.position
        let shouldAnimate = lastFrame != nil && currentPosition.distance(to: targetPosition) > 0.5

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        faceView.bounds = targetBounds
        faceView.layer.position = targetPosition
        CATransaction.commit()

        if shouldAnimate {
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = currentPosition
            animation.toValue = targetPosition
            animation.duration = PomodoroStyle.timerTransitionDuration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.86, 0.22, 1)
            animation.isRemovedOnCompletion = true
            if #available(iOS 15.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            }
            faceView.layer.add(animation, forKey: "pomodoro.timerFace.position")
        }

        lastFrame = targetFrame
    }
}

final class PomodoroTimerFaceUIView: UIView {
    private let timeLabel = UILabel()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        timeLabel.font = .pomodoroRoundedFont(size: 96, weight: .bold, monospacedDigits: true)
        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.56
        timeLabel.textColor = .label

        titleLabel.font = .pomodoroRoundedFont(size: 36, weight: .bold, monospacedDigits: false)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.64

        addSubview(timeLabel)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        timeLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 116)
        titleLabel.frame = CGRect(x: 0, y: 116, width: bounds.width, height: 50)
    }

    func update(content: PomodoroTimerFaceContent) {
        timeLabel.text = content.timeText
        titleLabel.text = content.title
        titleLabel.textColor = UIColor(content.titleColor)
    }
}

private extension UIFont {
    static func pomodoroRoundedFont(size: CGFloat, weight: UIFont.Weight, monospacedDigits: Bool) -> UIFont {
        let base = monospacedDigits
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        guard let roundedDescriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: roundedDescriptor, size: size)
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(x - point.x, y - point.y)
    }
}
#else
struct PomodoroHighRefreshTimerFace: View {
    let content: PomodoroTimerFaceContent
    let frame: CGRect?

    var body: some View {
        if let frame {
            PomodoroTimerFace(
                timeText: content.timeText,
                title: content.title,
                titleColor: content.titleColor
            )
            .position(x: frame.midX, y: frame.midY)
            .animation(PomodoroStyle.timerTransitionAnimation, value: frame)
        }
    }
}
#endif
