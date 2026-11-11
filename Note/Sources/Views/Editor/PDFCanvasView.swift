import SwiftUI
import PDFKit
import PencilKit

/// PDFView 위에 페이지마다 PKCanvasView를 오버레이로 얹는 편집 캔버스.
struct PDFCanvasView: UIViewRepresentable {
    let model: EditorModel

    func makeUIView(context: Context) -> ResponderPDFView {
        let view = ResponderPDFView()
        view.autoScales = true
        view.displayMode = model.isWhiteboard ? .singlePage : .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.backgroundColor = .secondarySystemBackground
        view.pageOverlayViewProvider = context.coordinator
        view.isInMarkupMode = true
        context.coordinator.pdfView = view

        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.pageChanged), name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateUIView(_ view: ResponderPDFView, context: Context) {
        context.coordinator.apply(model: model)
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    static func dismantleUIView(_ view: ResponderPDFView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: view)
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate {
        let model: EditorModel
        weak var pdfView: PDFView?
        let toolPicker = PKToolPicker()

        private var canvases: [PDFPage: PKCanvasView] = [:]
        private var pageForCanvas: [ObjectIdentifier: PDFPage] = [:]
        private var appliedStructureVersion = -1
        private var appliedNavigationToken = -1
        private var appliedPolicy: PKCanvasViewDrawingPolicy?
        private var appliedFilter: PlaybackFilter?
        private var isApplyingPlayback = false
        private var didShowToolPicker = false

        init(model: EditorModel) {
            self.model = model
        }

        // MARK: Apply model state

        func apply(model: EditorModel) {
            guard let pdfView, let document = model.document else { return }

            if appliedStructureVersion != model.structureVersion {
                appliedStructureVersion = model.structureVersion
                let targetIndex = model.currentPageIndex
                canvases.removeAll()
                pageForCanvas.removeAll()
                pdfView.document = nil
                pdfView.document = document.pdfDocument
                configureScale(pdfView)
                if let page = document.pdfDocument.page(at: targetIndex) { pdfView.go(to: page) }
                appliedNavigationToken = model.navigationToken
            }

            if appliedNavigationToken != model.navigationToken {
                appliedNavigationToken = model.navigationToken
                if let page = document.pdfDocument.page(at: model.currentPageIndex) { pdfView.go(to: page) }
            }

            if appliedPolicy != model.drawingPolicy {
                appliedPolicy = model.drawingPolicy
                for canvas in canvases.values { canvas.drawingPolicy = model.drawingPolicy }
            }

            let filter = model.playbackFilter
            if filter != appliedFilter {
                appliedFilter = filter
                applyPlayback(filter)
            }

            if !didShowToolPicker, pdfView.window != nil {
                didShowToolPicker = true
                toolPicker.setVisible(true, forFirstResponder: pdfView)
                pdfView.becomeFirstResponder()
            }
        }

        private func configureScale(_ pdfView: PDFView) {
            pdfView.autoScales = true
            let fit = pdfView.scaleFactorForSizeToFit
            pdfView.minScaleFactor = max(fit * 0.4, 0.05)
            pdfView.maxScaleFactor = max(fit * 6, 4)
        }

        private func applyPlayback(_ filter: PlaybackFilter?) {
            isApplyingPlayback = true
            defer { isApplyingPlayback = false }
            for (page, canvas) in canvases {
                guard let index = pdfView?.document?.index(for: page) else { continue }
                let full = model.drawing(forPageAt: index)
                if let filter {
                    canvas.drawing = filter.apply(to: full)
                    canvas.isUserInteractionEnabled = false
                } else {
                    canvas.drawing = full
                    canvas.isUserInteractionEnabled = true
                }
            }
        }

        @objc func pageChanged() {
            guard let pdfView, let page = pdfView.currentPage, let doc = pdfView.document else { return }
            let index = doc.index(for: page)
            model.noteVisiblePage(index)
        }

        // MARK: PDFPageOverlayViewProvider

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            if let existing = canvases[page] { return existing }
            guard let doc = view.document else { return nil }
            let index = doc.index(for: page)

            let canvas = PKCanvasView()
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.isScrollEnabled = false
            canvas.drawingPolicy = model.drawingPolicy
            canvas.delegate = self
            let full = model.drawing(forPageAt: index)
            canvas.drawing = appliedFilter.map { $0.apply(to: full) } ?? full
            canvas.isUserInteractionEnabled = appliedFilter == nil
            toolPicker.addObserver(canvas)
            toolPicker.setVisible(true, forFirstResponder: canvas)
            if let tool = toolPicker.selectedToolItem.tool { canvas.tool = tool }

            canvases[page] = canvas
            pageForCanvas[ObjectIdentifier(canvas)] = page
            return canvas
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let canvas = overlayView as? PKCanvasView else { return }
            toolPicker.removeObserver(canvas)
            canvases[page] = nil
            pageForCanvas[ObjectIdentifier(canvas)] = nil
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingPlayback,
                  let page = pageForCanvas[ObjectIdentifier(canvasView)],
                  let index = pdfView?.document?.index(for: page) else { return }
            model.updateDrawing(canvasView.drawing, forPageAt: index)
        }
    }
}

/// 도구 피커를 붙이기 위해 첫 응답자가 될 수 있는 PDFView.
final class ResponderPDFView: PDFView {
    override var canBecomeFirstResponder: Bool { true }
}
