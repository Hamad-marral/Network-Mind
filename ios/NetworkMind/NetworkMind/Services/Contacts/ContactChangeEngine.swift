import Foundation

/// A Contacts change-history event, decoupled from the Contacts framework for testability.
enum ContactChangeEvent: Equatable, Sendable {
    /// The system discarded history; the client must resynchronize from scratch.
    case dropEverything
    case added(String)
    case updated(String)
    case deleted(String)
}

struct ContactChangeSummary: Equatable, Sendable {
    /// Added contact identifiers, in event order, excluding contacts deleted later in the batch.
    var addedIdentifiers: [String] = []
    var deletedIdentifiers: Set<String> = []
    var requiresFullResync = false
}

enum ContactChangeHistoryParser {
    /// Reduces raw history events into the net set of additions/deletions.
    static func summarize(_ events: [ContactChangeEvent]) -> ContactChangeSummary {
        var summary = ContactChangeSummary()
        var added: [String] = []
        var addedSet = Set<String>()
        for event in events {
            switch event {
            case .dropEverything:
                // Everything after a drop is a full re-listing of the address book, not real
                // additions: signal a diff-based resync instead.
                summary.requiresFullResync = true
            case .added(let id):
                summary.deletedIdentifiers.remove(id)
                if addedSet.insert(id).inserted { added.append(id) }
            case .updated:
                break
            case .deleted(let id):
                if addedSet.remove(id) != nil {
                    added.removeAll { $0 == id }
                } else {
                    summary.deletedIdentifiers.insert(id)
                }
            }
        }
        summary.addedIdentifiers = added
        return summary
    }

    /// Identifiers present in `current` but not in `previous`, in a stable order.
    static func diff(previous: Set<String>, current: Set<String>) -> [String] {
        current.subtracting(previous).sorted()
    }
}

/// Abstraction over `CNContactStore` used by the engine.
protocol ContactHistorySource {
    func currentHistoryToken() -> Data?
    func changes(since token: Data) throws -> (events: [ContactChangeEvent], token: Data?)
    func allContactIdentifiers() throws -> Set<String>
}

/// Persists the change-history token and a snapshot of known contact identifiers (the
/// snapshot powers the diff fallback when the token is invalidated).
protocol ContactSyncStateStore: AnyObject {
    var historyToken: Data? { get set }
    var knownIdentifiers: Set<String>? { get set }
}

/// Determines which contacts are new since the last sync.
struct ContactChangeEngine {
    enum Outcome: Equatable {
        /// First run: existing contacts were recorded as the baseline, none are "new".
        case baselineEstablished(count: Int)
        case incremental(newIdentifiers: [String])
        /// Token invalid/expired or history dropped: computed via snapshot diff.
        case diffFallback(newIdentifiers: [String])

        var newIdentifiers: [String] {
            switch self {
            case .baselineEstablished: []
            case .incremental(let ids), .diffFallback(let ids): ids
            }
        }
    }

    let source: ContactHistorySource
    let state: ContactSyncStateStore

    func detectNewContacts() throws -> Outcome {
        guard let token = state.historyToken, let snapshot = state.knownIdentifiers else {
            // Never import the user's whole address book: only contacts added from now on count.
            let all = try source.allContactIdentifiers()
            state.knownIdentifiers = all
            state.historyToken = source.currentHistoryToken()
            return .baselineEstablished(count: all.count)
        }

        let result: (events: [ContactChangeEvent], token: Data?)
        do {
            result = try source.changes(since: token)
        } catch {
            return .diffFallback(newIdentifiers: try resyncByDiff(snapshot: snapshot))
        }

        let summary = ContactChangeHistoryParser.summarize(result.events)
        if summary.requiresFullResync {
            return .diffFallback(newIdentifiers: try resyncByDiff(snapshot: snapshot))
        }

        let newIDs = summary.addedIdentifiers.filter { !snapshot.contains($0) }
        var updated = snapshot
        updated.subtract(summary.deletedIdentifiers)
        updated.formUnion(summary.addedIdentifiers)
        state.knownIdentifiers = updated
        state.historyToken = result.token ?? source.currentHistoryToken()
        return .incremental(newIdentifiers: newIDs)
    }

    private func resyncByDiff(snapshot: Set<String>) throws -> [String] {
        let current = try source.allContactIdentifiers()
        let newIDs = ContactChangeHistoryParser.diff(previous: snapshot, current: current)
        state.knownIdentifiers = current
        state.historyToken = source.currentHistoryToken()
        return newIDs
    }
}

/// `UserDefaults` + file-backed implementation of `ContactSyncStateStore`.
final class DefaultsContactSyncStateStore: ContactSyncStateStore {
    private let defaults: UserDefaults
    private let snapshotURL: URL
    private static let tokenKey = "contacts.historyToken"

    init(defaults: UserDefaults = .standard, snapshotURL: URL? = nil) {
        self.defaults = defaults
        self.snapshotURL = snapshotURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("contact-snapshot.json")
    }

    var historyToken: Data? {
        get { defaults.data(forKey: Self.tokenKey) }
        set { defaults.set(newValue, forKey: Self.tokenKey) }
    }

    var knownIdentifiers: Set<String>? {
        get {
            guard let data = try? Data(contentsOf: snapshotURL),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else { return nil }
            return Set(ids)
        }
        set {
            guard let newValue else {
                try? FileManager.default.removeItem(at: snapshotURL)
                return
            }
            try? FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(newValue.sorted()) {
                try? data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    func reset() {
        historyToken = nil
        knownIdentifiers = nil
    }
}
