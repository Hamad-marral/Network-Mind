import Foundation
import SwiftData

/// A business opportunity surfaced by analysis.
@Model
final class Opportunity {
    var id: UUID = UUID()
    var title: String = ""
    var why: String = ""
    var suggestedNextStep: String = ""
    var isDone: Bool = false
    var createdAt: Date = Date()
    var meeting: Meeting?

    init(title: String, why: String = "", suggestedNextStep: String = "") {
        self.id = UUID()
        self.title = title
        self.why = why
        self.suggestedNextStep = suggestedNextStep
        self.createdAt = Date()
    }
}

/// An action item, owned by me or by the other person.
@Model
final class TodoItem {
    var id: UUID = UUID()
    var task: String = ""
    var ownerRaw: String = TodoOwner.me.rawValue
    var dueHint: String = ""
    var isDone: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
    var meeting: Meeting?

    init(task: String, owner: TodoOwner = .me, dueHint: String = "") {
        self.id = UUID()
        self.task = task
        self.ownerRaw = owner.rawValue
        self.dueHint = dueHint
        self.createdAt = Date()
    }

    var owner: TodoOwner {
        get { TodoOwner(rawValue: ownerRaw) ?? .me }
        set { ownerRaw = newValue.rawValue }
    }

    func setDone(_ done: Bool) {
        isDone = done
        completedAt = done ? Date() : nil
    }
}

/// A follow-up message drafted by the AI. The user always reviews and taps send.
@Model
final class FollowUpDraft {
    var id: UUID = UUID()
    var channelRaw: String = FollowUpChannel.whatsapp.rawValue
    var toneRaw: String = FollowUpTone.friendly.rawValue
    var subject: String = ""
    var body: String = ""
    var statusRaw: String = DraftStatus.draft.rawValue
    var language: String = "en"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sentAt: Date?
    var meeting: Meeting?
    var person: Person?

    init(channel: FollowUpChannel, tone: FollowUpTone, subject: String = "", body: String, language: String = "en") {
        self.id = UUID()
        self.channelRaw = channel.rawValue
        self.toneRaw = tone.rawValue
        self.subject = subject
        self.body = body
        self.language = language
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var channel: FollowUpChannel {
        get { FollowUpChannel(rawValue: channelRaw) ?? .whatsapp }
        set { channelRaw = newValue.rawValue }
    }

    var tone: FollowUpTone {
        get { FollowUpTone(rawValue: toneRaw) ?? .friendly }
        set { toneRaw = newValue.rawValue }
    }

    var status: DraftStatus {
        get { DraftStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
}

/// An auditable record of a consent acknowledgment.
@Model
final class ConsentRecord {
    var id: UUID = UUID()
    var kindRaw: String = ConsentKind.legalTerms.rawValue
    var acknowledgedAt: Date = Date()
    /// The exact text the user agreed to.
    var text: String = ""
    var appVersion: String = ""
    var sessionID: UUID?

    init(kind: ConsentKind, text: String, sessionID: UUID? = nil, acknowledgedAt: Date = Date()) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.text = text
        self.sessionID = sessionID
        self.acknowledgedAt = acknowledgedAt
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var kind: ConsentKind { ConsentKind(rawValue: kindRaw) ?? .legalTerms }
}
