import SwiftUI
import VisionKit

/// Live business-card text scanner. Point the camera at a card and tap "Use card": the
/// recognized lines are parsed and shown in the Add Person form for confirmation.
struct BusinessCardScanFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var parsed: ParsedBusinessCard?

    var body: some View {
        Group {
            if let parsed {
                AddPersonView(prefill: NewContactInput(
                    name: parsed.name,
                    jobTitle: parsed.title,
                    organization: parsed.company,
                    phone: parsed.phones.first ?? "",
                    email: parsed.emails.first ?? ""
                ), source: .businessCard)
            } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                NavigationStack {
                    BusinessCardScannerView { lines in
                        parsed = BusinessCardParser.parse(lines: lines)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scan card")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    }
                }
            } else {
                NavigationStack {
                    ContentUnavailableView(
                        "Scanner unavailable",
                        systemImage: "camera.metering.unknown",
                        description: Text(DataScannerViewController.isSupported
                            ? "Allow camera access in Settings to scan business cards."
                            : "Card scanning needs a device with a camera and Live Text support. You can add the person manually.")
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    }
                }
            }
        }
    }
}

struct BusinessCardScannerView: View {
    let onCapture: ([String]) -> Void
    @State private var lines: [String] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(lines: $lines)
            VStack(spacing: 8) {
                Text(lines.isEmpty ? "Hold the card inside the frame" : "\(lines.count) lines detected")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                Button {
                    onCapture(lines)
                } label: {
                    Label("Use card", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(lines.isEmpty)
            }
            .padding()
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var lines: [String]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(lines: $lines) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var lines: Binding<[String]>

        init(lines: Binding<[String]>) { self.lines = lines }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems)
        }

        /// Keep the text in reading order (top to bottom, then left to right).
        private func update(_ items: [RecognizedItem]) {
            let texts: [(String, CGPoint)] = items.compactMap { item in
                if case .text(let text) = item { return (text.transcript, text.bounds.topLeft) }
                return nil
            }
            lines.wrappedValue = texts
                .sorted { abs($0.1.y - $1.1.y) > 8 ? $0.1.y < $1.1.y : $0.1.x < $1.1.x }
                .map(\.0)
        }
    }
}
