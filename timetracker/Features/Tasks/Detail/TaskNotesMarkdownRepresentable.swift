import MarkdownView
import SwiftUI

#if canImport(UIKit)
    struct TaskNotesMarkdownRepresentable: UIViewRepresentable {
        let markdown: String
        let theme: MarkdownTheme
        @Binding var measuredHeight: CGFloat
        let onOpenURL: (URL) -> Void

        func makeUIView(context: Context) -> MarkdownTextView {
            let view = MarkdownTextView()
            view.setContentHuggingPriority(.required, for: .vertical)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            context.coordinator.configureLinks(on: view)
            return view
        }

        func updateUIView(_ view: MarkdownTextView, context: Context) {
            context.coordinator.measuredHeight = $measuredHeight
            context.coordinator.onOpenURL = onOpenURL
            context.coordinator.update(view: view, markdown: markdown, theme: theme)
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize,
            uiView: MarkdownTextView,
            context: Context
        ) -> CGSize? {
            context.coordinator.sizeThatFits(proposal, for: uiView)
        }

        func makeCoordinator() -> TaskNotesMarkdownCoordinator {
            TaskNotesMarkdownCoordinator(
                measuredHeight: $measuredHeight,
                onOpenURL: onOpenURL
            )
        }
    }
#elseif canImport(AppKit)
    struct TaskNotesMarkdownRepresentable: NSViewRepresentable {
        let markdown: String
        let theme: MarkdownTheme
        @Binding var measuredHeight: CGFloat
        let onOpenURL: (URL) -> Void

        func makeNSView(context: Context) -> MarkdownTextView {
            let view = MarkdownTextView()
            view.setContentHuggingPriority(.required, for: .vertical)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            context.coordinator.configureLinks(on: view)
            return view
        }

        func updateNSView(_ view: MarkdownTextView, context: Context) {
            context.coordinator.measuredHeight = $measuredHeight
            context.coordinator.onOpenURL = onOpenURL
            context.coordinator.update(view: view, markdown: markdown, theme: theme)
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize,
            nsView: MarkdownTextView,
            context: Context
        ) -> CGSize? {
            context.coordinator.sizeThatFits(proposal, for: nsView)
        }

        func makeCoordinator() -> TaskNotesMarkdownCoordinator {
            TaskNotesMarkdownCoordinator(
                measuredHeight: $measuredHeight,
                onOpenURL: onOpenURL
            )
        }
    }
#endif
