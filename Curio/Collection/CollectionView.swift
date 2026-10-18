import SwiftUI
import SwiftData
import QuickLook
import QuickLookThumbnailing

/// Home screen: a grid of every scanned object, with a button to scan a new one.
struct CollectionView: View {
    @Query(sort: \CollectedObject.createdAt, order: .reverse) private var collectedObjects: [CollectedObject]
    @State private var isShowingScanner = false
    /// Setting this opens Quick Look's interactive 3D/AR viewer for that model.
    @State private var previewModelURL: URL?

    private let gridColumns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if collectedObjects.isEmpty {
                    ContentUnavailableView(
                        "No Curios Yet",
                        systemImage: "cube.transparent",
                        description: Text("Scan an object to start your collection.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(collectedObjects) { collectedObject in
                                Button {
                                    previewModelURL = collectedObject.modelURL
                                } label: {
                                    CollectedObjectCell(collectedObject: collectedObject)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Collection")
            .safeAreaInset(edge: .bottom) {
                Button {
                    isShowingScanner = true
                } label: {
                    Label("Scan Object", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.glassProminent)
                .padding(.bottom, 8)
            }
        }
        .fullScreenCover(isPresented: $isShowingScanner) {
            ScannerView()
        }
        .quickLookPreview($previewModelURL)
    }
}

/// A square tile showing a rendered thumbnail of the object's 3D model.
private struct CollectedObjectCell: View {
    let collectedObject: CollectedObject

    var body: some View {
        VStack(spacing: 6) {
            ModelThumbnailView(modelURL: collectedObject.modelURL)
                .aspectRatio(1, contentMode: .fit)
                .background(.quaternary, in: .rect(cornerRadius: 16))
            Text(collectedObject.createdAt, format: .dateTime.month().day())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Renders a still image of a `.usdz` file using Quick Look's thumbnail generator.
private struct ModelThumbnailView: View {
    let modelURL: URL
    @State private var thumbnail: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: modelURL) {
            let request = QLThumbnailGenerator.Request(
                fileAt: modelURL,
                size: CGSize(width: 200, height: 200),
                scale: displayScale,
                representationTypes: .thumbnail
            )
            let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = representation?.uiImage
        }
    }
}

#Preview {
    CollectionView()
        .modelContainer(for: CollectedObject.self, inMemory: true)
}
