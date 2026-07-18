import MarkdownView
import SwiftUI

struct TaskNotesMarkdownPreview: View {
    @Environment(\.openURL) private var openURL
    @State private var measuredHeight: CGFloat = 0

    let markdown: String

    var body: some View {
        TaskNotesMarkdownRepresentable(
            markdown: markdown,
            theme: MarkdownTheme(),
            measuredHeight: $measuredHeight,
            onOpenURL: { url in
                openURL(url)
            }
        )
        .frame(
            maxWidth: .infinity,
            minHeight: measuredHeight,
            idealHeight: measuredHeight > 0 ? measuredHeight : nil,
            maxHeight: measuredHeight > 0 ? measuredHeight : nil,
            alignment: .topLeading
        )
        .accessibilityIdentifier("task.detail.notes.markdown")
    }
}

@MainActor
final class TaskNotesMarkdownCoordinator {
    var measuredHeight: Binding<CGFloat>
    var onOpenURL: (URL) -> Void
    var lastMarkdown: String?
    var lastTheme: MarkdownTheme?
    var width: CGFloat = 0

    init(
        measuredHeight: Binding<CGFloat>,
        onOpenURL: @escaping (URL) -> Void
    ) {
        self.measuredHeight = measuredHeight
        self.onOpenURL = onOpenURL
    }

    func configureLinks(on view: MarkdownTextView) {
        view.linkHandler = { [weak self] payload, _, _ in
            guard let self, let url = Self.url(from: payload) else { return }
            onOpenURL(url)
        }
    }

    func update(
        view: MarkdownTextView,
        markdown: String,
        theme: MarkdownTheme
    ) {
        configureLinks(on: view)
        guard lastMarkdown != markdown || lastTheme != theme else {
            updateMeasuredHeight(for: view)
            return
        }

        view.theme = theme
        view.setMarkdown(markdown)
        view.invalidateIntrinsicContentSize()
        lastMarkdown = markdown
        lastTheme = theme
        updateMeasuredHeight(for: view)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        for view: MarkdownTextView
    ) -> CGSize? {
        let candidateWidth = proposal.width ?? width
        let fittingWidth = candidateWidth.isFinite && candidateWidth > 0
            ? candidateWidth
            : view.bounds.width
        guard fittingWidth.isFinite, fittingWidth > 0 else { return nil }

        width = fittingWidth
        let height = measuredHeight(for: view, width: fittingWidth)
        publish(height)
        return CGSize(width: fittingWidth, height: height)
    }

    private func updateMeasuredHeight(for view: MarkdownTextView) {
        guard width.isFinite, width > 0 else { return }
        publish(measuredHeight(for: view, width: width))
    }

    private func measuredHeight(
        for view: MarkdownTextView,
        width: CGFloat
    ) -> CGFloat {
        ceil(view.boundingSize(for: width).height)
    }

    private func publish(_ height: CGFloat) {
        guard abs(height - measuredHeight.wrappedValue) > 0.5 else { return }
        let binding = measuredHeight
        DispatchQueue.main.async {
            binding.wrappedValue = height
        }
    }

    private static func url(from payload: LinkPayload) -> URL? {
        switch payload {
        case let .url(url):
            url
        case let .string(value):
            URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
