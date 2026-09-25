import UIKit

@MainActor
extension FireTopicDetailModalRouter {
    func presentDeleteConfirmation(
        postNumber: UInt32,
        onConfirm: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: "删除回复",
            message: "确认删除 #\(postNumber) 吗？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            onConfirm()
        })
        viewController?.present(alert, animated: true)
    }

    func presentNotice(title: String = "提示", message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        viewController?.present(alert, animated: true)
    }
}
