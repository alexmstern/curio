import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        CollectionView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: CollectedObject.self, inMemory: true)
}
