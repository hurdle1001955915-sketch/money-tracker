import SwiftUI
import UIKit

// MARK: - DragSelectableList
// 写真アプリのような「1本指でスクロールしながらなぞり選択」を実現するコンポーネント
// UICollectionView + カスタムジェスチャーで実装

struct DragSelectableList<Item: Identifiable, Content: View>: UIViewRepresentable where Item.ID: Hashable {

    let items: [Item]
    @Binding var selectedItems: Set<Item.ID>
    @Binding var isSelectionMode: Bool
    let cellContent: (Item, Bool) -> Content
    var rowHeight: CGFloat = 80
    var enableHaptics: Bool = true

    func makeUIView(context: Context) -> UICollectionView {
        let layout = createLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true

        // 複数選択を有効化
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true

        // セル登録
        collectionView.register(
            HostingCollectionViewCell<Content>.self,
            forCellWithReuseIdentifier: HostingCollectionViewCell<Content>.reuseIdentifier
        )

        // Coordinator設定
        let coordinator = context.coordinator
        coordinator.collectionView = collectionView
        coordinator.setupDataSource(for: collectionView)
        collectionView.delegate = coordinator

        // カスタムなぞり選択ジェスチャーを追加
        coordinator.setupSelectionGestures(for: collectionView)

        // 初期スナップショット適用
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item.ID>()
        snapshot.appendSections([0])
        snapshot.appendItems(items.map { $0.id })
        coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
        coordinator.cachedItemIds = items.map { $0.id }

        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        let coordinator = context.coordinator

        // IDリストが変わった場合のみスナップショット更新（厳密な比較）
        let newItemIds = items.map { $0.id }
        let itemsChanged = coordinator.cachedItemIds != newItemIds

        // 選択状態の変更を検出
        let selectionChanged = coordinator.selectedItems != selectedItems

        // Coordinatorのデータを更新（先に更新することで整合性を保つ）
        coordinator.items = items
        coordinator.isSelectionMode = isSelectionMode
        coordinator.selectedItems = selectedItems
        coordinator.cellContent = cellContent
        coordinator.rowHeight = rowHeight
        coordinator.onSelectionChanged = { [self] newSelection in
            DispatchQueue.main.async {
                self.selectedItems = newSelection
            }
        }

        // アイテムが変更された場合のみスナップショット更新
        if itemsChanged {
            coordinator.cachedItemIds = newItemIds
            var snapshot = NSDiffableDataSourceSnapshot<Int, Item.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(newItemIds)
            coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
        }

        // 選択状態が変更された場合、セルを更新
        if selectionChanged {
            updateVisibleCells(collectionView: collectionView, coordinator: coordinator)
            syncUICollectionViewSelection(collectionView: collectionView, coordinator: coordinator)
        }
    }

    func makeCoordinator() -> DragSelectableCoordinator<Item, Content> {
        DragSelectableCoordinator(
            items: items,
            selectedItems: selectedItems,
            isSelectionMode: isSelectionMode,
            cellContent: cellContent,
            rowHeight: rowHeight,
            enableHaptics: enableHaptics,
            onSelectionChanged: { [self] newSelection in
                self.selectedItems = newSelection
            }
        )
    }

    private func createLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(rowHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(rowHeight)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 0

        return UICollectionViewCompositionalLayout(section: section)
    }

    /// 表示中のセルを安全に更新
    private func updateVisibleCells(collectionView: UICollectionView, coordinator: DragSelectableCoordinator<Item, Content>) {
        for cell in collectionView.visibleCells {
            guard let hostingCell = cell as? HostingCollectionViewCell<Content>,
                  let indexPath = collectionView.indexPath(for: cell) else {
                continue // returnではなくcontinueで他のセルも処理
            }

            guard indexPath.item < items.count else { continue }

            let item = items[indexPath.item]
            let isSelected = selectedItems.contains(item.id)
            hostingCell.configure(with: cellContent(item, isSelected))
        }
    }

    /// UICollectionViewの内部選択状態をBindingと同期
    private func syncUICollectionViewSelection(collectionView: UICollectionView, coordinator: DragSelectableCoordinator<Item, Content>) {
        // 現在のUI選択状態を取得
        let currentUISelection = Set(collectionView.indexPathsForSelectedItems?.compactMap { indexPath -> Item.ID? in
            guard indexPath.item < items.count else { return nil }
            return items[indexPath.item].id
        } ?? [])

        // 差分がある場合のみ更新
        guard currentUISelection != selectedItems else { return }

        // 選択解除すべきもの
        for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
            guard indexPath.item < items.count else { continue }
            let itemId = items[indexPath.item].id
            if !selectedItems.contains(itemId) {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }

        // 新規選択すべきもの
        for (index, item) in items.enumerated() {
            if selectedItems.contains(item.id) {
                let indexPath = IndexPath(item: index, section: 0)
                if !(collectionView.indexPathsForSelectedItems?.contains(indexPath) ?? false) {
                    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                }
            }
        }
    }
}

// MARK: - Coordinator

final class DragSelectableCoordinator<Item: Identifiable, Content: View>: NSObject,
    UICollectionViewDelegate, UIGestureRecognizerDelegate where Item.ID: Hashable {

    var items: [Item]
    var selectedItems: Set<Item.ID>
    var isSelectionMode: Bool
    var cellContent: (Item, Bool) -> Content
    var rowHeight: CGFloat
    var enableHaptics: Bool
    var onSelectionChanged: (Set<Item.ID>) -> Void

    // キャッシュ（スナップショット適用判定用）
    var cachedItemIds: [Item.ID] = []

    weak var collectionView: UICollectionView?
    var dataSource: UICollectionViewDiffableDataSource<Int, Item.ID>?

    // ジェスチャー関連
    private var longPressGesture: UILongPressGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    private var isDragSelecting = false
    private var dragStartIndexPath: IndexPath?
    private var lastSelectedIndexPath: IndexPath?
    private var autoScrollTimer: Timer?
    private var autoScrollDirection: AutoScrollDirection = .none

    // ハプティクス
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    enum AutoScrollDirection {
        case none, up, down
    }

    init(
        items: [Item],
        selectedItems: Set<Item.ID>,
        isSelectionMode: Bool,
        cellContent: @escaping (Item, Bool) -> Content,
        rowHeight: CGFloat,
        enableHaptics: Bool,
        onSelectionChanged: @escaping (Set<Item.ID>) -> Void
    ) {
        self.items = items
        self.selectedItems = selectedItems
        self.isSelectionMode = isSelectionMode
        self.cellContent = cellContent
        self.rowHeight = rowHeight
        self.enableHaptics = enableHaptics
        self.onSelectionChanged = onSelectionChanged
        super.init()
        selectionFeedback.prepare()
        impactFeedback.prepare()
    }

    func setupDataSource(for collectionView: UICollectionView) {
        dataSource = UICollectionViewDiffableDataSource<Int, Item.ID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, itemId -> UICollectionViewCell? in
            guard let self = self else { return nil }

            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: HostingCollectionViewCell<Content>.reuseIdentifier,
                for: indexPath
            ) as? HostingCollectionViewCell<Content>

            if let item = self.items.first(where: { $0.id == itemId }) {
                // 常に最新のselectedItemsを参照
                let isSelected = self.selectedItems.contains(itemId)
                cell?.configure(with: self.cellContent(item, isSelected))
            }

            return cell
        }
    }

    // MARK: - カスタムジェスチャー設定

    func setupSelectionGestures(for collectionView: UICollectionView) {
        // 長押しジェスチャー（なぞり選択開始のトリガー）
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.2
        longPress.delegate = self
        collectionView.addGestureRecognizer(longPress)
        self.longPressGesture = longPress

        // パンジェスチャー（なぞり選択の継続）
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        collectionView.addGestureRecognizer(pan)
        self.panGesture = pan
    }

    // MARK: - ジェスチャーハンドラ

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard isSelectionMode, let collectionView = collectionView else { return }

        let location = gesture.location(in: collectionView)

        switch gesture.state {
        case .began:
            // 長押し開始位置のセルを特定
            if let indexPath = collectionView.indexPathForItem(at: location) {
                isDragSelecting = true
                dragStartIndexPath = indexPath
                lastSelectedIndexPath = indexPath

                // 開始セルを選択
                toggleSelectionAt(indexPath)

                if enableHaptics {
                    impactFeedback.impactOccurred()
                }
            }

        case .changed:
            guard isDragSelecting else { return }
            handleDragAt(location: location, in: collectionView)

        case .ended, .cancelled, .failed:
            endDragSelection()

        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelectionMode, isDragSelecting, let collectionView = collectionView else { return }

        let location = gesture.location(in: collectionView)

        switch gesture.state {
        case .changed:
            handleDragAt(location: location, in: collectionView)

        case .ended, .cancelled, .failed:
            endDragSelection()

        default:
            break
        }
    }

    /// ドラッグ中の処理
    private func handleDragAt(location: CGPoint, in collectionView: UICollectionView) {
        // 自動スクロール判定
        let visibleRect = collectionView.bounds
        let topThreshold: CGFloat = 50
        let bottomThreshold = visibleRect.height - 50

        if location.y < topThreshold {
            startAutoScroll(direction: .up)
        } else if location.y > bottomThreshold {
            startAutoScroll(direction: .down)
        } else {
            stopAutoScroll()
        }

        // 現在位置のセルを選択
        let adjustedLocation = CGPoint(x: location.x, y: location.y + collectionView.contentOffset.y - collectionView.bounds.origin.y)
        if let indexPath = collectionView.indexPathForItem(at: location) {
            selectRangeTo(indexPath)
        }
    }

    /// 範囲選択
    private func selectRangeTo(_ currentIndexPath: IndexPath) {
        guard let startIndexPath = dragStartIndexPath,
              let lastIndexPath = lastSelectedIndexPath,
              currentIndexPath != lastIndexPath else { return }

        // 開始位置から現在位置までの範囲を選択
        let minIndex = min(startIndexPath.item, currentIndexPath.item)
        let maxIndex = max(startIndexPath.item, currentIndexPath.item)

        for i in minIndex...maxIndex {
            guard i < items.count else { continue }
            let indexPath = IndexPath(item: i, section: 0)
            let itemId = items[i].id

            if !selectedItems.contains(itemId) {
                selectedItems.insert(itemId)
                updateCellAppearance(at: indexPath, isSelected: true)

                if enableHaptics {
                    selectionFeedback.selectionChanged()
                }
            }
        }

        lastSelectedIndexPath = currentIndexPath
        onSelectionChanged(selectedItems)
    }

    /// 単一セルの選択トグル
    private func toggleSelectionAt(_ indexPath: IndexPath) {
        guard indexPath.item < items.count else { return }

        let itemId = items[indexPath.item].id

        if selectedItems.contains(itemId) {
            selectedItems.remove(itemId)
            updateCellAppearance(at: indexPath, isSelected: false)
        } else {
            selectedItems.insert(itemId)
            updateCellAppearance(at: indexPath, isSelected: true)
        }

        onSelectionChanged(selectedItems)
    }

    /// 自動スクロール開始
    private func startAutoScroll(direction: AutoScrollDirection) {
        guard autoScrollDirection != direction else { return }
        stopAutoScroll()

        autoScrollDirection = direction
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.performAutoScroll()
        }
    }

    /// 自動スクロール停止
    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDirection = .none
    }

    /// 自動スクロール実行
    private func performAutoScroll() {
        guard let collectionView = collectionView else { return }

        let scrollAmount: CGFloat = 10

        var newOffset = collectionView.contentOffset
        switch autoScrollDirection {
        case .up:
            newOffset.y = max(0, newOffset.y - scrollAmount)
        case .down:
            let maxY = collectionView.contentSize.height - collectionView.bounds.height
            newOffset.y = min(maxY, newOffset.y + scrollAmount)
        case .none:
            return
        }

        collectionView.setContentOffset(newOffset, animated: false)

        // スクロール後に現在位置のセルを選択
        if let gesture = panGesture {
            let location = gesture.location(in: collectionView)
            if let indexPath = collectionView.indexPathForItem(at: location) {
                selectRangeTo(indexPath)
            }
        }
    }

    /// ドラッグ選択終了
    private func endDragSelection() {
        isDragSelecting = false
        dragStartIndexPath = nil
        lastSelectedIndexPath = nil
        stopAutoScroll()
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 長押しとパンは同時認識を許可
        if gestureRecognizer == longPressGesture && otherGestureRecognizer == panGesture {
            return true
        }
        if gestureRecognizer == panGesture && otherGestureRecognizer == longPressGesture {
            return true
        }
        // スクロールとも共存（ドラッグ選択中でなければ）
        if !isDragSelecting {
            return true
        }
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // パンジェスチャーは、ドラッグ選択中のみ開始
        if gestureRecognizer == panGesture {
            return isDragSelecting
        }
        // 長押しは選択モード時のみ
        if gestureRecognizer == longPressGesture {
            return isSelectionMode
        }
        return true
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isDragSelecting else { return } // ドラッグ選択中はスキップ
        guard indexPath.item < items.count else { return }

        let itemId = items[indexPath.item].id
        selectedItems.insert(itemId)

        if enableHaptics {
            selectionFeedback.selectionChanged()
        }

        onSelectionChanged(selectedItems)
        updateCellAppearance(at: indexPath, isSelected: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard !isDragSelecting else { return } // ドラッグ選択中はスキップ
        guard indexPath.item < items.count else { return }

        let itemId = items[indexPath.item].id
        selectedItems.remove(itemId)

        if enableHaptics {
            selectionFeedback.selectionChanged()
        }

        onSelectionChanged(selectedItems)
        updateCellAppearance(at: indexPath, isSelected: false)
    }

    // MARK: - セル更新

    private func updateCellAppearance(at indexPath: IndexPath, isSelected: Bool) {
        guard let cell = collectionView?.cellForItem(at: indexPath) as? HostingCollectionViewCell<Content>,
              indexPath.item < items.count else { return }

        let item = items[indexPath.item]
        cell.configure(with: cellContent(item, isSelected))
    }

    func updateAllVisibleCells() {
        guard let collectionView = collectionView else { return }

        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let hostingCell = cell as? HostingCollectionViewCell<Content>,
                  indexPath.item < items.count else { continue }

            let item = items[indexPath.item]
            let isSelected = selectedItems.contains(item.id)
            hostingCell.configure(with: cellContent(item, isSelected))
        }
    }
}

// MARK: - HostingCollectionViewCell

final class HostingCollectionViewCell<Content: View>: UICollectionViewCell {

    static var reuseIdentifier: String { "HostingCollectionViewCell" }

    private var hostingController: UIHostingController<Content>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with content: Content) {
        if let hostingController = hostingController {
            hostingController.rootView = content
            hostingController.view.invalidateIntrinsicContentSize()
        } else {
            let controller = UIHostingController(rootView: content)
            controller.view.backgroundColor = .clear
            controller.view.translatesAutoresizingMaskIntoConstraints = false

            contentView.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])

            hostingController = controller
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // hostingControllerは再利用するので保持
        // rootViewは configure で上書きされる
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)

        if let hostingController = hostingController {
            let targetSize = CGSize(
                width: layoutAttributes.frame.width,
                height: UIView.layoutFittingCompressedSize.height
            )
            let size = hostingController.view.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            attributes.frame.size.height = size.height
        }

        return attributes
    }
}
