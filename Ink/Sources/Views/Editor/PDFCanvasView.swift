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
        // PDFKit의 페이지 접근성 요소 조회가 렌더링과 같은 CGPDFPage 락을 재진입해 크래시를 일으키므로
        // 페이지 하위 요소를 접근성 트리에서 제외한다. 필기 캔버스는 PencilKit이 별도로 노출한다.
        view.accessibilityElementsHidden = true
        view.accessibilityIdentifier = "editor.pdfView"
        context.coordinator.pdfView = view
        view.onDidMoveToWindow = { [weak coordinator = context.coordinator] in coordinator?.showToolPickerIfPossible() }

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
        private var appliedZoomToken = 0
        private var appliedPolicy: PKCanvasViewDrawingPolicy?
        private var appliedFilter: PlaybackFilter?
        private var isApplyingPlayback = false
        private var didShowToolPicker = false

        init(model: EditorModel) {
            self.model = model
            super.init()
        }

        // MARK: Apply model state

        func apply(model: EditorModel) {
            guard let pdfView, let document = model.document else { return }

            if appliedStructureVersion != model.structureVersion {
                appliedStructureVersion = model.structureVersion
                let targetIndex = model.currentPageIndex
                let previousScale = pdfView.document == nil ? nil : pdfView.scaleFactor
                canvases.removeAll()
                pageForCanvas.removeAll()
                pdfView.document = nil
                pdfView.document = document.pdfDocument
                configureScale(pdfView)
                if let previousScale, !model.isWhiteboard { pdfView.scaleFactor = previousScale }
                if let page = document.pdfDocument.page(at: targetIndex) { pdfView.go(to: page) }
                appliedNavigationToken = model.navigationToken
            }

            if appliedNavigationToken != model.navigationToken {
                appliedNavigationToken = model.navigationToken
                if let page = document.pdfDocument.page(at: model.currentPageIndex) { pdfView.go(to: page) }
            }

            if appliedZoomToken != model.zoomRequest.token {
                appliedZoomToken = model.zoomRequest.token
                let factor: CGFloat = model.zoomRequest.delta > 0 ? 1.25 : 0.8
                pdfView.scaleFactor = min(max(pdfView.scaleFactor * factor, pdfView.minScaleFactor), pdfView.maxScaleFactor)
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

            showToolPickerIfPossible()
        }

        func showToolPickerIfPossible() {
            guard !didShowToolPicker, let pdfView, pdfView.window != nil else { return }
            didShowToolPicker = true
            toolPicker.setVisible(true, forFirstResponder: pdfView)
            pdfView.becomeFirstResponder()
            focusCurrentCanvas()
        }

        /// 현재 페이지의 캔버스를 첫 응답자로 만들어 도구 피커가 보이게 한다.
        /// SwiftUI 호스팅 환경에서는 PDFView 자체의 첫 응답자 상태가 곧 풀리므로 캔버스를 사용한다.
        func focusCurrentCanvas() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let pdfView = self.pdfView else { return }
                if self.canvases.values.contains(where: { $0.isFirstResponder }) { return }
                let target = pdfView.currentPage.flatMap { self.canvases[$0] } ?? self.canvases.values.first
                target?.becomeFirstResponder()
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
            if #available(iOS 26, *) {
                if let tool = toolPicker.selectedToolItem.tool { canvas.tool = tool }
            } else {
                canvas.tool = toolPicker.selectedTool
            }

            canvases[page] = canvas
            pageForCanvas[ObjectIdentifier(canvas)] = page
            if didShowToolPicker { focusCurrentCanvas() }
            return canvas
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let canvas = overlayView as? PKCanvasView else { return }
            toolPicker.removeObserver(canvas)
            canvases[page] = nil
            pageForCanvas[ObjectIdentifier(canvas)] = nil
            if canvas.isFirstResponder { focusCurrentCanvas() }
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
    var onDidMoveToWindow: (() -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onDidMoveToWindow?() }
    }
}
