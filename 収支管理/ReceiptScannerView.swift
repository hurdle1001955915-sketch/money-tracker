import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Receipt Scanner View

struct ReceiptScannerView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var parser = ReceiptParser()
    
    private enum PickerMode: Identifiable {
        case camera
        case library

        var id: Int { self == .camera ? 0 : 1 }
        var sourceType: UIImagePickerController.SourceType {
            self == .camera ? .camera : .photoLibrary
        }
    }

    @State private var selectedImage: UIImage?
    @State private var pickerMode: PickerMode? = nil

    // 入力フィールド
    @State private var date = Date()
    @State private var amountText = ""
    @State private var categoryName = ""
    @State private var memo = ""

    @State private var showDatePicker = false
    @State private var showSourceDialog = false

    // Validation
    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    // Permissions & Alerts
    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var showNoCameraAlert = false
    @State private var showMissingUsageDescriptionAlert = false
    @State private var missingUsageMessage = ""

    private var categories: [Category] {
        dataStore.expenseCategories
    }

    private var parsedAmount: Int? {
        let trimmed = amountText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Int(trimmed), v > 0 else { return nil }
        return v
    }

    private var canSave: Bool {
        parsedAmount != nil && !categoryName.isEmpty
    }

    var body: some View {
        NavigationStack {
            mainContent
                .background(Color(.systemGroupedBackground))
                .navigationTitle("レシート読取")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { topToolbar }
                .sheet(item: $pickerMode) { mode in
                    ImagePicker(image: $selectedImage, sourceType: mode.sourceType)
                }
                .sheet(isPresented: $showDatePicker) {
                    ReceiptDatePickerSheet(date: $date)
                }
                .onChange(of: selectedImage) { _, newImage in
                    guard let image = newImage else { return }
                    Task {
                        await parser.parseReceipt(from: image)
                        applyParseResult()
                    }
                }
                .onAppear {
                    if let first = categories.first {
                        categoryName = first.name
                    }
                }
                .confirmationDialog("画像の選択", isPresented: $showSourceDialog, titleVisibility: .visible) {
                    Button("カメラで撮影") { openCamera() }
                    Button("写真から選択") { openPhotoLibrary() }
                    Button("キャンセル", role: .cancel) {}
                }
                .alert("カメラが利用できません", isPresented: $showNoCameraAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("このデバイスではカメラが利用できません。")
                }
                .alert("アクセス許可が必要です", isPresented: $showPermissionAlert) {
                    Button("設定を開く") { openSettingsApp() }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text(permissionAlertMessage)
                }
                .alert("設定が不足しています", isPresented: $showMissingUsageDescriptionAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(missingUsageMessage)
                }
                .alert("入力エラー", isPresented: $showValidationAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(validationMessage)
                }
        }
    }

    // MARK: - Main UI (split for compiler)

    @ViewBuilder
    private var mainContent: some View {
        if selectedImage == nil {
            imageSelectionArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    imageHeader
                    errorBanner
                    parsedResultBanner
                    inputFormSection
                }
                .padding()
            }
        }
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("保存") { saveTransaction() }
                .fontWeight(.semibold)
                .disabled(!canSave)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var imageHeader: some View {
        if let image = selectedImage {
            HStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("レシート画像")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Button("変更") { showImageSourceOptions() }
                        .font(.caption)
                        .foregroundStyle(Color.themeBlue)
                }

                Spacer()

                if parser.isProcessing {
                    ProgressView()
                        .padding(.trailing, 8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = parser.error {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var parsedResultBanner: some View {
        if let result = parser.result {
            parseResultSection(result)
        }
    }

    private var imageSelectionArea: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("レシートの写真を選択してください")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("AIが自動で金額や日付を読み取ります")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button { openCamera() } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                        Text("カメラで撮影")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.themeBlue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button { openPhotoLibrary() } label: {
                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.title3)
                        Text("写真から選択")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .padding()
    }

    private func parseResultSection(_ result: ReceiptParseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("読み取り完了")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            if let store = result.storeName {
                HStack {
                    Text("店舗:")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(store)
                }
                .font(.caption)
            }

            if let date = result.date {
                HStack {
                    Text("日付:")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(date.fullDateString)
                }
                .font(.caption)
            }

            if let amount = result.totalAmount {
                HStack {
                    Text("合計:")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(amount.currencyFormatted)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.themeBlue)
                }
                .font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var inputFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            Text("取引情報を確認")
                .font(.headline)

            // 日付
            HStack {
                Text("日付")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Button {
                    dismissKeyboard()
                    showDatePicker = true
                } label: {
                    HStack {
                        Text(date.fullDateString)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 金額
            HStack {
                Text("金額")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .fontWeight(.semibold)
                Text("円")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // カテゴリ
            HStack {
                Text("カテゴリ")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $categoryName) {
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // メモ
            HStack(alignment: .top) {
                Text("メモ")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                    .padding(.top, 4)
                TextField("メモ（任意）", text: $memo, axis: .vertical)
                    .lineLimit(3...5)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Actions

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func hasUsageDescription(_ key: String) -> Bool {
        guard let obj = Bundle.main.object(forInfoDictionaryKey: key) else { return false }
        if let s = obj as? String {
            return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func openCamera() {
        dismissKeyboard()

        guard hasUsageDescription("NSCameraUsageDescription") else {
            missingUsageMessage = "カメラの使用理由（NSCameraUsageDescription）が設定されていません。Info.plist に説明文を追加してください。"
            showMissingUsageDescriptionAlert = true
            return
        }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showNoCameraAlert = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            pickerMode = .camera
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        pickerMode = .camera
                    } else {
                        permissionAlertMessage = "カメラへのアクセスが拒否されています。設定アプリから許可してください。"
                        showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            permissionAlertMessage = "カメラへのアクセスが拒否されています。設定アプリから許可してください。"
            showPermissionAlert = true
        @unknown default:
            permissionAlertMessage = "カメラへのアクセス状態を確認できませんでした。"
            showPermissionAlert = true
        }
    }

    private func openPhotoLibrary() {
        dismissKeyboard()

        guard hasUsageDescription("NSPhotoLibraryUsageDescription") else {
            missingUsageMessage = "写真ライブラリの使用理由（NSPhotoLibraryUsageDescription）が設定されていません。Info.plist に説明文を追加してください。"
            showMissingUsageDescriptionAlert = true
            return
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            pickerMode = .library
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        pickerMode = .library
                    } else {
                        permissionAlertMessage = "写真ライブラリへのアクセスが拒否されています。設定アプリから許可してください。"
                        showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            permissionAlertMessage = "写真ライブラリへのアクセスが拒否されています。設定アプリから許可してください。"
            showPermissionAlert = true
        @unknown default:
            permissionAlertMessage = "写真ライブラリへのアクセス状態を確認できませんでした。"
            showPermissionAlert = true
        }
    }

    private func openSettingsApp() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func showImageSourceOptions() {
        dismissKeyboard()
        showSourceDialog = true
    }

    private func applyParseResult() {
        guard let result = parser.result else { return }

        if let total = result.totalAmount {
            amountText = String(total)
        }
        if let parsedDate = result.date {
            date = parsedDate
        }
        if let store = result.storeName {
            memo = store
        }
    }

    private func saveTransaction() {
        dismissKeyboard()

        guard let amount = parsedAmount else {
            validationMessage = "金額を正しく入力してください。"
            showValidationAlert = true
            return
        }
        guard !categoryName.isEmpty else {
            validationMessage = "カテゴリを選択してください。"
            showValidationAlert = true
            return
        }

        // カテゴリ名からIDを解決（なければ作成）
        let cat = dataStore.createCategoryIfNeeded(name: categoryName, type: .expense)
        let tx = Transaction(
            date: date,
            type: .expense,
            amount: amount,
            categoryId: cat?.id,
            originalCategoryName: cat == nil ? categoryName : nil,
            memo: memo
        )

        dataStore.addTransaction(tx)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false

        if sourceType == .camera {
            picker.cameraDevice = .rear
            picker.cameraCaptureMode = .photo
            picker.videoQuality = .typeHigh
            picker.cameraFlashMode = .auto
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Date Picker Sheet

private struct ReceiptDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date

    var body: some View {
        NavigationStack {
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .onChange(of: date) { _, _ in
                    dismiss()
                }
                .navigationTitle("日付を選択")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ReceiptScannerView()
        .environmentObject(DataStore.shared)
}
