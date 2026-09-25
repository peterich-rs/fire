import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension FireComposerViewController {
    @objc func titleFieldChanged(_ sender: UITextField) {
        titleText = sender.text ?? ""
        errorMessage = nil
        scheduleAutosave()
        render()
    }

    @objc func tagFieldChanged(_ sender: UITextField) {
        tagInput = sender.text ?? ""
        performTagSearch(query: tagInput)
        render()
    }

    @objc func recipientFieldChanged(_ sender: UITextField) {
        recipientQuery = sender.text ?? ""
        performRecipientSearch(query: recipientQuery)
        render()
    }

    @objc func categoryButtonTapped() {
        let alert = UIAlertController(title: "选择分类", message: nil, preferredStyle: .actionSheet)
        for category in availableCategories {
            let title = categoryDisplayName(for: category)
            let summary = FireComposerCategoryGuidance.categorySheetSummary(for: category)
            let action = UIAlertAction(title: summary == nil ? title : "\(title) · \(summary ?? "")", style: .default) { [weak self] _ in
                guard let self else { return }
                selectedCategoryID = category.id
                applyCategoryTemplateIfNeeded()
                if tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tagResults = []
                } else {
                    performTagSearch(query: tagInput)
                }
                errorMessage = nil
                scheduleAutosave()
                render()
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = categoryButton
            popover.sourceRect = categoryButton.bounds
        }
        present(alert, animated: true)
    }

    @objc func previewButtonTapped() {
        previewMode.toggle()
        render()
    }

    @objc func imageButtonTapped() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc func markdownButtonTapped(_ sender: UIButton) {
        guard let action = FireMarkdownFormatAction(rawTag: sender.tag) else { return }
        applyMarkdownFormat(action)
    }

    func applyMarkdownFormat(_ action: FireMarkdownFormatAction) {
        let result = FireMarkdownInsertion.apply(
            action,
            text: bodyText,
            selectedRange: bodySelection
        )
        bodyText = result.text
        bodySelection = result.selectedRange
        updateTextViewSelection()
        bodyTextView.becomeFirstResponder()
        errorMessage = nil
        updateMentionSearch()
        scheduleAutosave()
        resolveShortUploadsIfNeeded()
        render()
    }

    func replaceText(in range: NSRange, with replacement: String) {
        let source = bodyText as NSString
        let safeRange = NSRange(
            location: min(max(range.location, 0), source.length),
            length: min(max(range.length, 0), max(0, source.length - range.location))
        )
        bodyText = source.replacingCharacters(in: safeRange, with: replacement)
        bodySelection = NSRange(
            location: safeRange.location + (replacement as NSString).length,
            length: 0
        )
        updateTextViewSelection()
        errorMessage = nil
        updateMentionSearch()
        scheduleAutosave()
        resolveShortUploadsIfNeeded()
    }

    func updateTextViewSelection() {
        if bodyTextView.text != bodyText {
            bodyTextView.text = bodyText
        }
        bodyTextView.selectedRange = bodySelection
    }

    func uploadImageData(_ bytes: Data, fileExtension: String, mimeType: String) {
        Task { [weak self] in
            guard let self else { return }
            isUploadingImage = true
            render()
            defer {
                isUploadingImage = false
                render()
            }
            do {
                let fileName = "fire-\(UUID().uuidString).\(fileExtension)"
                let result = try await viewModel.uploadImage(
                    fileName: fileName,
                    mimeType: mimeType,
                    bytes: bytes
                )
                let markdown = markdownForUpload(result)
                let prefix = bodySelection.location == 0 ? "" : "\n"
                replaceText(in: bodySelection, with: "\(prefix)\(markdown)\n")
                resolveShortUploadsIfNeeded()
                render()
            } catch {
                errorMessage = error.localizedDescription
                render()
            }
        }
    }

    func markdownForUpload(_ result: UploadResultState) -> String {
        let alt = result.originalFilename ?? "image"
        let width = result.thumbnailWidth ?? result.width
        let height = result.thumbnailHeight ?? result.height
        if let width, let height {
            return "![\(alt)|\(width)x\(height)](\(result.shortUrl))"
        }
        return "![\(alt)](\(result.shortUrl))"
    }

    func resolveShortUploadsIfNeeded() {
        uploadResolutionTask?.cancel()
        let missing = Array(
            Set(
                markdownImages
                    .map(\.urlString)
                    .filter { $0.hasPrefix("upload://") && resolvedUploads[$0] == nil }
            )
        )
        guard !missing.isEmpty else { return }

        uploadResolutionTask = Task {
            do {
                let resolved = try await viewModel.lookupUploadUrls(shortUrls: missing)
                guard !Task.isCancelled else { return }
                for item in resolved {
                    resolvedUploads[item.shortUrl] = item
                }
                render()
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
    }

    func resolvedURL(for rawValue: String) -> URL? {
        let resolvedValue: String
        if rawValue.hasPrefix("upload://") {
            guard let resolved = resolvedUploads[rawValue]?.url else {
                return nil
            }
            resolvedValue = resolved
        } else {
            resolvedValue = rawValue
        }

        if resolvedValue.hasPrefix("/") {
            return URL(string: "\(baseURLString)\(resolvedValue)")
        }
        return URL(string: resolvedValue)
    }

}
