import UIKit
import ChauffeurRemoteClient
import ChauffeurRemoteProtocol

/// Asks the user before an agent ends its own session to remove the worktree it works in, as the
/// Mac app does. The Mac waits for an answer while its app is open or while this phone shows the
/// session; either can answer, and the other's prompt goes away. Requests wait their turn; one
/// answered on the Mac, or whose session ended some other way, is dismissed.
///
/// The alert lives in its own window above the app, so it shows over sheets and the terminal, and a
/// sheet SwiftUI dismisses underneath it can't take it down unanswered.
@MainActor final class WorktreeRemovalPrompt {
    private weak var model: MobileAppModel?
    private var window: UIWindow?
    private var active: (request: WorktreeRemovalRequest, alert: UIAlertController)?
    /// An answer that failed, shown before anything else is asked.
    private var failure: UIAlertController?
    /// Requests already answered or dismissed, so an inventory that still lists one doesn't ask again.
    private var handled = Set<UUID>()
    /// True while a prompt whose request went away is animating out; the next one waits for it.
    private var dismissing = false

    func update(_ requests: [WorktreeRemovalRequest], model: MobileAppModel) {
        self.model = model
        let ids = Set(requests.map(\.id))
        handled.formIntersection(ids)
        if let active, !ids.contains(active.request.id) {
            // Answered on the Mac, or the session ended: nothing is left to answer.
            self.active = nil
            dismissing = true
            active.alert.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.dismissing = false
                self.hideWindowIfIdle()
                if let model = self.model { self.update(model.worktreeRemovalRequests, model: model) }
            }
            return
        }
        guard active == nil, failure == nil, !dismissing, let next = requests.first(where: { !handled.contains($0.id) }) else { return }
        present(next)
    }

    private func present(_ request: WorktreeRemovalRequest) {
        guard let host = hostController() else { return }
        let alert = UIAlertController(title: "End “\(request.sessionTitle)” and remove its worktree?", message: Self.message(request), preferredStyle: .alert)
        // The prompt arrives unasked, so the safe answer is the preferred one.
        let keep = UIAlertAction(title: "Keep Session", style: .cancel) { [weak self] _ in self?.finish(request, approve: false) }
        alert.addAction(keep)
        alert.addAction(UIAlertAction(title: "End Session and Remove", style: .destructive) { [weak self] _ in self?.finish(request, approve: true) })
        alert.preferredAction = keep
        alert.view.accessibilityIdentifier = "worktree-removal.prompt"
        active = (request, alert)
        handled.insert(request.id)
        host.present(alert, animated: true)
    }

    private func finish(_ request: WorktreeRemovalRequest, approve: Bool) {
        guard active?.request.id == request.id else { return }
        active = nil
        hideWindowIfIdle()
        guard let model else { return }
        Task { [weak self] in
            do {
                try await model.answerWorktreeRemoval(request, approve: approve)
            } catch {
                // An answer that never reached the Mac leaves the request pending: ask again once it is listed.
                self?.handled.remove(request.id)
                self?.showFailure(error)
                return
            }
            self?.update(model.worktreeRemovalRequests, model: model)
        }
    }

    private func showFailure(_ error: Error) {
        guard let host = hostController() else { return }
        let message = (error as? RemoteClientError)?.userMessage ?? error.localizedDescription
        let alert = UIAlertController(title: "The worktree wasn’t removed", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self else { return }
            self.failure = nil
            self.hideWindowIfIdle()
            if let model = self.model { self.update(model.worktreeRemovalRequests, model: model) }
        })
        failure = alert
        host.present(alert, animated: true)
    }

    /// The overlay window's root controller, creating the window on the app's foreground scene.
    private func hostController() -> UIViewController? {
        if let window, let root = window.rootViewController {
            window.isHidden = false
            return root
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false
        self.window = window
        return root
    }

    /// Hides the overlay once nothing is shown in it, handing touches and the keyboard back to the app.
    private func hideWindowIfIdle() {
        guard active == nil, failure == nil, !dismissing, let window else { return }
        window.isHidden = true
        self.window = nil
        let scene = window.windowScene
        scene?.windows.first { $0 !== window && !$0.isHidden && $0.windowLevel == .normal }?.makeKey()
    }

    static func message(_ request: WorktreeRemovalRequest) -> String {
        var lines = ["The agent asked to remove the worktree it is working in. Its session ends, and the checkout at \(request.path) is deleted."]
        if let outcome = request.branchOutcome { lines.append(outcome) }
        if request.lost.isEmpty { lines.append("Nothing is lost.") }
        else { lines.append("This loses:\n" + request.lost.map { "• \($0)" }.joined(separator: "\n")) }
        lines.append("If you keep the session, the agent keeps running and the worktree stays.")
        lines.append("You can turn off this question in Chauffeur’s settings on the Mac, under Runtime.")
        return lines.joined(separator: "\n\n")
    }
}
