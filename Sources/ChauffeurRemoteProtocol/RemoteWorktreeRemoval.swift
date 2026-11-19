import Foundation

/// An agent asked to remove the worktree it works in, which ends its session.
/// It waits for the user to approve or decline it in the Mac app or on a phone.
public struct WorktreeRemovalRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var sessionTitle: String
    public var worktreeID: UUID
    public var path: String
    public var branch: String?
    /// What happens to the branch, when the checkout is on one.
    public var branchOutcome: String?
    /// What the removal loses, as the agent's preview listed it.
    public var lost: [String]
    public var requestedAt: Date
    public init(id: UUID = UUID(), sessionID: UUID, sessionTitle: String, worktreeID: UUID, path: String, branch: String?, branchOutcome: String?, lost: [String], requestedAt: Date = Date()) {
        self.id = id; self.sessionID = sessionID; self.sessionTitle = sessionTitle; self.worktreeID = worktreeID
        self.path = path; self.branch = branch; self.branchOutcome = branchOutcome; self.lost = lost; self.requestedAt = requestedAt
    }
}

/// The user's answer to a `WorktreeRemovalRequest`. Approving ends the session and removes the worktree;
/// declining keeps both. An answer to a request that is gone does nothing.
public struct AnswerWorktreeRemovalRequest: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var approve: Bool

    public init(requestID: UUID, approve: Bool) {
        self.requestID = requestID; self.approve = approve
    }
}
