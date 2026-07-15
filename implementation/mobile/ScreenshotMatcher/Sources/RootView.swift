import SwiftUI

struct RootView: View {
    @StateObject private var sentStore = GalleryStore(kind: .sent)
    @StateObject private var receivedStore = GalleryStore(kind: .received)

    var body: some View {
        TabView {
            CameraView(sentStore: sentStore, receivedStore: receivedStore)
                .tabItem { Label("Camera", systemImage: "camera.fill") }

            GalleryView(store: sentStore, title: "Sent", emptyIcon: "paperplane", emptyText: "Photos you send will show up here.")
                .tabItem { Label("Sent", systemImage: "paperplane.fill") }

            GalleryView(store: receivedStore, title: "Received", emptyIcon: "photo.on.rectangle", emptyText: "Screenshots you receive will show up here.")
                .tabItem { Label("Received", systemImage: "photo.on.rectangle.fill") }
        }
    }
}

#Preview {
    RootView()
}
