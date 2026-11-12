import UIKit
import PencilKit

/// 페이지 객체 편집 이벤트를 모델로 전달한다.
@MainActor
protocol PageOverlayDelegate: AnyObject {
    func overlay(_ overlay: PageOverlayView, didMove objectID: UUID, to frame: CGRect)
    func overlay(_ overlay: PageOverlayView, didEditText objectID: UUID, text: String)
    func overlay(_ overlay: PageOverlayView, didSelect objectID: UUID?)
    func overlay(_ overlay: PageOverlayView, didDelete objectID: UUID)
}

/// 한 페이지의 오버레이. 아래에 객체 레이어, 위에 필기 캔버스를 둔다.
@MainActor
final class PageOverlayView: UIView {
    let canvas = PKCanvasView()
    let objectsLayer = UIView()
    weak var delegate: PageOverlayDelegate?
    private(set) var objectViews: [UUID: PageObjectView] = [:]
    private var isObjectMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        objectsLayer.backgroundColor = .clear
        addSubview(objectsLayer)
        addSubview(canvas)
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        objectsLayer.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        objectsLayer.frame = bounds
        canvas.frame = bounds
    }

    /// 객체 모드에서는 캔버스를 비활성화해 객체를 만질 수 있게 한다.
    func setObjectMode(_ enabled: Bool) {
        isObjectMode = enabled
        canvas.isUserInteractionEnabled = !enabled
        for view in objectViews.values { view.isEditable = enabled }
        if !enabled { select(nil) }
    }

    func select(_ id: UUID?) {
        for (key, view) in objectViews { view.isSelected = key == id }
    }

    /// 모델의 객체 목록과 화면을 맞춘다.
    func sync(objects: [PageObject], document: NotebookDocument) {
        let ids = Set(objects.map(\.id))
        for (id, view) in objectViews where !ids.contains(id) {
            view.removeFromSuperview()
            objectViews[id] = nil
        }
        for object in objects {
            if let view = objectViews[object.id] {
                if !view.isTracking { view.frame = object.frame }
                view.apply(object, document: document)
            } else {
                let view = PageObjectView(object: object, document: document)
                view.isEditable = isObjectMode
                view.onMoved = { [weak self] id, frame in
                    guard let self else { return }
                    self.delegate?.overlay(self, didMove: id, to: frame)
                }
                view.onTextChanged = { [weak self] id, text in
                    guard let self else { return }
                    self.delegate?.overlay(self, didEditText: id, text: text)
                }
                view.onSelected = { [weak self] id in
                    guard let self else { return }
                    self.select(id)
                    self.delegate?.overlay(self, didSelect: id)
                }
                view.onDelete = { [weak self] id in
                    guard let self else { return }
                    self.delegate?.overlay(self, didDelete: id)
                }
                objectsLayer.addSubview(view)
                objectViews[object.id] = view
            }
        }
    }

    @objc private func backgroundTapped() {
        select(nil)
        delegate?.overlay(self, didSelect: nil)
    }
}

/// 이미지·텍스트·스티커 하나를 표시하고 이동/크기 조절/편집 제스처를 처리한다.
@MainActor
final class PageObjectView: UIView, UITextViewDelegate {
    let objectID: UUID
    private var object: PageObject
    private let imageView = UIImageView()
    private let textView = UITextView()
    private let deleteButton = UIButton(type: .system)
    private(set) var isTracking = false

    var onMoved: ((UUID, CGRect) -> Void)?
    var onTextChanged: ((UUID, String) -> Void)?
    var onSelected: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?

    var isEditable = false {
        didSet {
            isUserInteractionEnabled = isEditable
            if !isEditable { isSelected = false; textView.resignFirstResponder() }
        }
    }

    var isSelected = false {
        didSet {
            layer.borderWidth = isSelected ? 2 : 0
            deleteButton.isHidden = !isSelected
            if !isSelected { textView.isEditable = false; textView.resignFirstResponder() }
        }
    }

    init(object: PageObject, document: NotebookDocument) {
        self.objectID = object.id
        self.object = object
        super.init(frame: object.frame)
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.cornerRadius = 4

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        addSubview(textView)

        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "xmark")
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        deleteButton.configuration = config
        deleteButton.isHidden = true
        deleteButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onDelete?(self.objectID)
        }, for: .touchUpInside)
        addSubview(deleteButton)

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        isUserInteractionEnabled = false
        apply(object, document: document)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ object: PageObject, document: NotebookDocument) {
        self.object = object
        switch object.kind {
        case .image(let name):
            imageView.isHidden = false
            textView.isHidden = true
            imageView.image = document.image(named: name)
        case .text(let text):
            imageView.isHidden = true
            textView.isHidden = false
            if !textView.isFirstResponder { textView.text = text }
            textView.font = .systemFont(ofSize: object.fontSize)
            textView.textColor = .black
        case .sticker(let emoji):
            imageView.isHidden = true
            textView.isHidden = false
            textView.text = emoji
            textView.font = .systemFont(ofSize: object.frame.height * 0.8)
            textView.textAlignment = .center
            textView.textContainerInset = .zero
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        textView.frame = bounds
        if case .sticker = object.kind {
            textView.font = .systemFont(ofSize: bounds.height * 0.8)
        }
        deleteButton.sizeToFit()
        deleteButton.frame = CGRect(x: bounds.maxX - 14, y: -14, width: 28, height: 28)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || (!deleteButton.isHidden && deleteButton.frame.contains(point))
    }

    @objc private func tap() {
        onSelected?(objectID)
    }

    @objc private func doubleTap() {
        guard object.isText else { return }
        onSelected?(objectID)
        textView.isEditable = true
        textView.isSelectable = true
        textView.becomeFirstResponder()
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard !textView.isFirstResponder else { return }
        if g.state == .began { isTracking = true; onSelected?(objectID) }
        let t = g.translation(in: superview)
        center = CGPoint(x: center.x + t.x, y: center.y + t.y)
        g.setTranslation(.zero, in: superview)
        if g.state == .ended || g.state == .cancelled {
            isTracking = false
            onMoved?(objectID, frame)
        }
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { isTracking = true; onSelected?(objectID) }
        let scale = g.scale
        let c = center
        let w = max(24, bounds.width * scale), h = max(24, bounds.height * scale)
        bounds = CGRect(x: 0, y: 0, width: w, height: h)
        center = c
        g.scale = 1
        if case .text = object.kind {
            textView.font = .systemFont(ofSize: max(8, (textView.font?.pointSize ?? object.fontSize) * scale))
        }
        if g.state == .ended || g.state == .cancelled {
            isTracking = false
            onMoved?(objectID, frame)
        }
    }

    // MARK: UITextViewDelegate

    nonisolated func textViewDidEndEditing(_ textView: UITextView) {
        MainActor.assumeIsolated {
            textView.isEditable = false
            textView.isSelectable = false
            onTextChanged?(objectID, textView.text ?? "")
        }
    }
}
