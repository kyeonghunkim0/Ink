import SwiftUI
import PDFKit
import PencilKit

/// PDFView 위에 페이지마다 PKCanvasView를 오버레이로 얹는 편집 캔버스.
struct PDFCanvasView: UIViewRepresentable {
    let model: EditorModel

    func makeUIView(context: Context) -> ResponderPDFView {
        let view = ResponderPDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        if model.isWhiteboard {
            view.displayDirection = .vertical
        } else {
            // 노트북은 한 번에 한 페이지만 보이는 가로 캐러셀.
            view.displayDirection = .horizontal
            view.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 24])
        }
        view.pageShadowsEnabled = true
        view.isFingerDrawingEnabled = model.isFingerDrawingEnabled
        view.backgroundColor = .secondarySystemBackground
        view.pageOverlayViewProvider = context.coordinator
        view.isInMarkupMode = true
        // PDFKit의 페이지 접근성 요소 조회가 렌더링과 같은 CGPDFPage 락을 재진입해 크래시를 일으키므로
        // 페이지 하위 요소를 접근성 트리에서 제외한다. 필기 캔버스는 PencilKit이 별도로 노출한다.
        view.accessibilityElementsHidden = true
        view.accessibilityIdentifier = "editor.pdfView"
        context.coordinator.pdfView = view
        view.onDidMoveToWindow = { [weak coordinator = context.coordinator] in coordinator?.showToolPickerIfPossible() }
        view.onSwipePastLastPage = { [weak coordinator = context.coordinator] in coordinator?.appendPageAfterLast() }

        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.pageChanged), name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateUIView(_ view: ResponderPDFView, context: Context) {
        context.coordinator.apply(model: model)
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    static func dismantleUIView(_ view: ResponderPDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate, PageOverlayDelegate {
        let model: EditorModel
        weak var pdfView: PDFView?
        let toolPicker = PKToolPicker()

        private var overlays: [PDFPage: PageOverlayView] = [:]
        private var pageForCanvas: [ObjectIdentifier: PDFPage] = [:]
        private var canvases: [PKCanvasView] { overlays.values.map(\.canvas) }
        private var appliedObjectsVersion = -1
        private var appliedObjectMode = false
        private var appliedSelection: UUID?
        private var appliedStructureVersion = -1
        private var appliedNavigationToken = -1
        private var appliedZoomToken = 0
        /// 직선 보정 후보. 펜을 멈춘 채 뗀 직후의 캔버스.
        private var pendingStraighten: (canvas: PKCanvasView, at: Date)?
        private var isStraightening = false
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
                toolPicker.colorUserInterfaceStyle = inkStyle(for: model)
                let targetIndex = model.currentPageIndex
                let previousScale = pdfView.document == nil ? nil : pdfView.scaleFactor
                overlays.removeAll()
                pageForCanvas.removeAll()
                pdfView.document = nil
                pdfView.document = document.pdfDocument
                configureScale(pdfView)
                if let previousScale { pdfView.scaleFactor = previousScale }
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
                for canvas in canvases { canvas.drawingPolicy = model.drawingPolicy }
                (pdfView as? ResponderPDFView)?.isFingerDrawingEnabled = model.isFingerDrawingEnabled
            }

            if appliedObjectsVersion != model.objectsVersion {
                appliedObjectsVersion = model.objectsVersion
                syncObjects()
            }
            if appliedObjectMode != model.isObjectModeEnabled {
                appliedObjectMode = model.isObjectModeEnabled
                for overlay in overlays.values { overlay.setObjectMode(appliedObjectMode) }
                if !appliedObjectMode { focusCurrentCanvas() }
            }
            if appliedSelection != model.selectedObjectID {
                appliedSelection = model.selectedObjectID
                for overlay in overlays.values { overlay.select(appliedSelection) }
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
            focusCurrentCanvas()
        }

        /// 현재 페이지의 캔버스를 첫 응답자로 만들어 도구 피커가 보이게 한다.
        /// SwiftUI 호스팅 환경에서는 PDFView 자체의 첫 응답자 상태가 곧 풀리므로 캔버스를 사용한다.
        func focusCurrentCanvas() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let pdfView = self.pdfView else { return }
                if self.canvases.contains(where: { $0.isFirstResponder }) { return }
                let target = pdfView.currentPage.flatMap { self.overlays[$0]?.canvas } ?? self.canvases.first
                target?.becomeFirstResponder()
            }
        }

        private func configureScale(_ pdfView: PDFView) {
            pdfView.autoScales = true
            let fit = pdfView.scaleFactorForSizeToFit
            pdfView.minScaleFactor = max(fit * 0.4, 0.05)
            pdfView.maxScaleFactor = max(fit * 6, 4)
            if model.isWhiteboard {
                // 화이트보드는 처음에 보드 전체가 보이도록 맞춤 배율로 연다.
                // 뷰 크기가 아직 정해지기 전이면 맞춤 배율이 틀리므로 레이아웃 뒤에 다시 맞춘다.
                pdfView.autoScales = false
                pdfView.scaleFactor = fit
                (pdfView as? ResponderPDFView)?.fitsOnNextLayout = true
            }
        }

        private func applyPlayback(_ filter: PlaybackFilter?) {
            isApplyingPlayback = true
            defer { isApplyingPlayback = false }
            for (page, overlay) in overlays {
                guard let index = pdfView?.document?.index(for: page) else { continue }
                let full = model.drawing(forPageAt: index)
                let canvas = overlay.canvas
                if let filter {
                    canvas.drawing = filter.apply(to: full)
                    canvas.isUserInteractionEnabled = false
                } else {
                    canvas.drawing = full
                    canvas.isUserInteractionEnabled = !model.isObjectModeEnabled
                }
            }
        }

        /// 방금 끝난 스트로크가 직선 후보면 직선으로 바꾼다.
        private func straightenIfNeeded(_ canvas: PKCanvasView) {
            guard let pending = pendingStraighten, pending.canvas === canvas,
                  Date().timeIntervalSince(pending.at) < 1.0 else { return }
            pendingStraighten = nil
            var drawing = canvas.drawing
            guard let last = drawing.strokes.last, isInking(canvas.tool),
                  let line = StrokeStraightener.straightened(last) else { return }
            drawing.strokes[drawing.strokes.count - 1] = line
            isStraightening = true
            canvas.drawing = drawing
            isStraightening = false
        }

        private func isInking(_ tool: PKTool) -> Bool {
            tool is PKInkingTool
        }

        /// 마지막 페이지에서 왼쪽으로 더 넘기면 새 페이지를 뒤에 추가하고 그 페이지로 간다.
        func appendPageAfterLast() {
            guard !model.isWhiteboard, model.pageCount > 0 else { return }
            model.addPage(after: model.pageCount - 1)
        }

        @objc func pageChanged() {
            guard let pdfView, let page = pdfView.currentPage, let doc = pdfView.document else { return }
            let index = doc.index(for: page)
            model.noteVisiblePage(index)
        }

        /// PencilKit은 다크 모드에서 검정 잉크를 흰색으로 뒤집어 보여 주므로,
        /// 잉크 색 표시는 시스템 테마가 아니라 용지 색에 맞춘다.
        private func inkStyle(for model: EditorModel) -> UIUserInterfaceStyle {
            model.manifest.paperColor == .dark ? .dark : .light
        }

        // MARK: PDFPageOverlayViewProvider

        private func syncObjects() {
            guard let document = model.document, let doc = pdfView?.document else { return }
            for (page, overlay) in overlays {
                let index = doc.index(for: page)
                overlay.sync(objects: model.objects(forPageAt: index), document: document)
            }
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            if let existing = overlays[page] { return existing }
            guard let doc = view.document, let document = model.document else { return nil }
            let index = doc.index(for: page)

            let overlay = PageOverlayView(frame: page.bounds(for: .mediaBox))
            overlay.delegate = self
            overlay.sync(objects: model.objects(forPageAt: index), document: document)
            overlay.setObjectMode(model.isObjectModeEnabled)
            overlay.select(model.selectedObjectID)
            let canvas = overlay.canvas
            canvas.overrideUserInterfaceStyle = inkStyle(for: model)
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.isScrollEnabled = false
            canvas.drawingPolicy = model.drawingPolicy
            canvas.delegate = self
            let full = model.drawing(forPageAt: index)
            canvas.drawing = appliedFilter.map { $0.apply(to: full) } ?? full
            canvas.isUserInteractionEnabled = appliedFilter == nil
            let hold = StrokeHoldObserver(target: nil, action: nil)
            hold.onTouchEnded = { [weak self, weak canvas] held in
                guard let self, let canvas else { return }
                self.pendingStraighten = held >= StrokeStraightener.holdDuration ? (canvas, Date()) : nil
            }
            canvas.addGestureRecognizer(hold)
            toolPicker.addObserver(canvas)
            toolPicker.setVisible(true, forFirstResponder: canvas)
            if #available(iOS 26, *) {
                if let tool = toolPicker.selectedToolItem.tool { canvas.tool = tool }
            } else {
                canvas.tool = toolPicker.selectedTool
            }

            overlays[page] = overlay
            pageForCanvas[ObjectIdentifier(canvas)] = page
            if didShowToolPicker { focusCurrentCanvas() }
            return overlay
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let overlay = overlayView as? PageOverlayView else { return }
            let canvas = overlay.canvas
            toolPicker.removeObserver(canvas)
            overlays[page] = nil
            pageForCanvas[ObjectIdentifier(canvas)] = nil
            if canvas.isFirstResponder { focusCurrentCanvas() }
        }

        // MARK: PageOverlayDelegate

        func overlay(_ overlay: PageOverlayView, didMove objectID: UUID, to frame: CGRect) {
            model.moveObject(objectID, to: frame)
        }

        func overlay(_ overlay: PageOverlayView, didEditText objectID: UUID, text: String) {
            model.updateObjectText(objectID, text: text)
        }

        func overlay(_ overlay: PageOverlayView, didSelect objectID: UUID?) {
            model.selectedObjectID = objectID
            appliedSelection = objectID
            for other in overlays.values where other !== overlay { other.select(nil) }
        }

        func overlay(_ overlay: PageOverlayView, didDelete objectID: UUID) {
            model.deleteObject(objectID)
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingPlayback, !isStraightening,
                  let page = pageForCanvas[ObjectIdentifier(canvasView)],
                  let index = pdfView?.document?.index(for: page) else { return }
            straightenIfNeeded(canvasView)
            model.updateDrawing(canvasView.drawing, forPageAt: index)
        }
    }
}

/// 윈도우에 붙는 시점을 알려주는 PDFView. 첫 응답자는 페이지 캔버스가 맡는다.
/// 내부 스크롤 뷰의 제스처를 손가락 전용으로 바꿔 펜 입력이 지연 없이 캔버스로 가게 한다.
final class ResponderPDFView: PDFView {
    var onDidMoveToWindow: (() -> Void)?
    /// 손가락 필기 중에는 두 손가락으로만 스크롤/페이지 넘김을 한다.
    var isFingerDrawingEnabled = false {
        didSet { if isFingerDrawingEnabled != oldValue { tuneScrollViews() } }
    }

    /// 마지막 페이지에서 다음 페이지 방향으로 충분히 끌었다 놓았을 때 호출된다.
    var onSwipePastLastPage: (() -> Void)?
    private var observedPans: Set<ObjectIdentifier> = []
    private var panStartedOnLastPage = false
    /// 이만큼 왼쪽으로 끌면 "놓으면 추가" 상태가 된다.
    private let addPageThreshold: CGFloat = 90
    private var isAddPageArmed = false
    private let addPageHint = AddPageHintView()

    /// 페이지가 한 장뿐이면 페이지 뷰 컨트롤러의 스크롤 뷰가 팬을 받지 않으므로, 뷰 자체에서 끌기를 감지한다.
    private lazy var singlePagePan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSinglePagePan))
        pan.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        pan.cancelsTouchesInView = false
        pan.delaysTouchesEnded = false
        pan.delegate = singlePagePanDelegate
        return pan
    }()
    private let singlePagePanDelegate = SimultaneousGestureDelegate()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onDidMoveToWindow?()
            if singlePagePan.view == nil { addGestureRecognizer(singlePagePan) }
            if addPageHint.superview == nil { addSubview(addPageHint) }
        }
    }

    @objc private func handleSinglePagePan(_ pan: UIPanGestureRecognizer) {
        guard document?.pageCount == 1 else { return }
        trackAddPagePan(pan)
    }

    @objc private func handlePagePan(_ pan: UIPanGestureRecognizer) {
        guard (document?.pageCount ?? 0) > 1 else { return }
        trackAddPagePan(pan)
    }

    /// 마지막 페이지에서 왼쪽으로 끄는 동안 안내를 보여 주고, 임계치를 넘긴 채 놓으면 페이지를 추가한다.
    private func trackAddPagePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            panStartedOnLastPage = isOnLastPage && displayDirection == .horizontal
            isAddPageArmed = false
        case .changed:
            guard panStartedOnLastPage else { return }
            let pulled = -pan.translation(in: self).x
            let progress = max(0, min(1, pulled / addPageThreshold))
            isAddPageArmed = pulled >= addPageThreshold
            addPageHint.update(progress: progress, armed: isAddPageArmed)
        case .ended:
            let shouldAdd = panStartedOnLastPage && isAddPageArmed
            addPageHint.hide()
            if shouldAdd {
                // 되돌아가는 바운스 애니메이션이 끝난 뒤에 추가해야 페이지 뷰 컨트롤러가 중간에 멈추지 않는다.
                whenSettled(pan.view as? UIScrollView) { [weak self] in self?.onSwipePastLastPage?() }
            }
            panStartedOnLastPage = false
            isAddPageArmed = false
        case .cancelled, .failed:
            addPageHint.hide()
            panStartedOnLastPage = false
            isAddPageArmed = false
        default:
            break
        }
    }

    /// 스크롤 뷰의 드래그·감속·바운스가 모두 끝나면 실행한다.
    private func whenSettled(_ scrollView: UIScrollView?, attempt: Int = 0, _ body: @escaping () -> Void) {
        let busy = scrollView.map { $0.isDragging || $0.isDecelerating || $0.isTracking } ?? false
        if !busy || attempt > 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { body() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.whenSettled(scrollView, attempt: attempt + 1, body)
            }
        }
    }

    private var isOnLastPage: Bool {
        guard let document, let page = currentPage else { return false }
        return document.index(for: page) == document.pageCount - 1
    }

    /// 다음 레이아웃에서 문서 전체가 보이도록 배율을 맞춘다(화이트보드 초기 열기).
    var fitsOnNextLayout = false

    override func layoutSubviews() {
        super.layoutSubviews()
        let hintSize = addPageHint.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        addPageHint.bounds = CGRect(origin: .zero, size: hintSize)
        addPageHint.center = CGPoint(x: bounds.maxX - hintSize.width / 2 - 20, y: bounds.midY)
        bringSubviewToFront(addPageHint)
        if fitsOnNextLayout, bounds.width > 0, document != nil {
            fitsOnNextLayout = false
            let fit = scaleFactorForSizeToFit
            minScaleFactor = max(fit * 0.4, 0.05)
            maxScaleFactor = max(fit * 6, 4)
            scaleFactor = fit
        }
        tuneScrollViews()
    }

    private func tuneScrollViews() {
        var queue: [UIView] = [self]
        while let view = queue.popLast() {
            if let scrollView = view as? UIScrollView {
                scrollView.delaysContentTouches = false
                scrollView.canCancelContentTouches = false
                let direct = [UITouch.TouchType.direct.rawValue as NSNumber]
                scrollView.panGestureRecognizer.allowedTouchTypes = direct
                scrollView.panGestureRecognizer.minimumNumberOfTouches = isFingerDrawingEnabled ? 2 : 1
                singlePagePan.minimumNumberOfTouches = isFingerDrawingEnabled ? 2 : 1
                scrollView.pinchGestureRecognizer?.allowedTouchTypes = direct
                let id = ObjectIdentifier(scrollView.panGestureRecognizer)
                if !observedPans.contains(id) {
                    observedPans.insert(id)
                    scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePagePan))
                }
            }
            if view is PKCanvasView { continue }
            queue.append(contentsOf: view.subviews)
        }
    }
}

/// 단일 페이지용 팬이 PDFView·캔버스 제스처와 함께 인식되게 하는 델리게이트.
private final class SimultaneousGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// 마지막 페이지에서 왼쪽으로 끌 때 "놓으면 새 페이지 추가" 안내. 끈 거리만큼 나타나고 임계치를 넘으면 강조된다.
@MainActor
final class AddPageHintView: UIVisualEffectView {
    private let icon = UIImageView()
    private let label = UILabel()

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        layer.cornerRadius = 22
        clipsToBounds = true
        isUserInteractionEnabled = false
        alpha = 0
        accessibilityIdentifier = "editor.addPageHint"

        icon.contentMode = .scaleAspectFit
        icon.tintColor = .label
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .label
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
        ])
        update(progress: 0, armed: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `progress`는 0...1(끈 거리 / 임계치). `armed`면 놓았을 때 페이지가 추가된다.
    func update(progress: CGFloat, armed: Bool) {
        layer.removeAllAnimations()
        isHidden = false
        alpha = min(1, progress * 1.4)
        let scale = 0.85 + 0.15 * progress
        transform = CGAffineTransform(scaleX: scale, y: scale)
        icon.image = UIImage(systemName: armed ? "plus.circle.fill" : "plus.circle")
        icon.tintColor = armed ? .tintColor : .label
        label.text = armed ? "놓으면 새 페이지 추가" : "더 끌어서 새 페이지 추가"
        if let superview { superview.setNeedsLayout() }
    }

    func hide() {
        UIView.animate(withDuration: 0.2) { self.alpha = 0 } completion: { _ in
            if self.alpha == 0 { self.isHidden = true }
        }
    }
}
