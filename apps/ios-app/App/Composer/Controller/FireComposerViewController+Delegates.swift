import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension FireComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        bodyText = textView.text ?? ""
        bodySelection = textView.selectedRange
        errorMessage = nil
        updateMentionSearch()
        scheduleAutosave()
        resolveShortUploadsIfNeeded()
        render()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        bodySelection = textView.selectedRange
        updateMentionSearch()
    }
}

extension FireComposerViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let type = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first(where: { $0.conforms(to: .image) }) ?? .jpeg
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.render()
                    return
                }
                guard let data else {
                    self.errorMessage = "读取图片失败。"
                    self.render()
                    return
                }
                self.uploadImageData(
                    data,
                    fileExtension: type.preferredFilenameExtension ?? "jpg",
                    mimeType: type.preferredMIMEType ?? "image/jpeg"
                )
            }
        }
    }
}
