import SwiftUI

struct GalleryView: View {
    @ObservedObject var store: GalleryStore
    let title: String
    let emptyIcon: String
    let emptyText: String

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView(title, systemImage: emptyIcon, description: Text(emptyText))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(store.items) { item in
                                NavigationLink(value: item) {
                                    thumbnail(for: item)
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle(title)
            .navigationDestination(for: GalleryItem.self) { item in
                ImageDetailView(store: store, item: item)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for item: GalleryItem) -> some View {
        if let image = store.image(for: item) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 110)
                .clipped()
                .cornerRadius(6)
        } else {
            Rectangle()
                .fill(.gray.opacity(0.2))
                .frame(height: 110)
                .cornerRadius(6)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}

struct ImageDetailView: View {
    @ObservedObject var store: GalleryStore
    let item: GalleryItem
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if let image = store.image(for: item) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                .background(Color.black)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Photo", image: Image(uiImage: image)))
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "exclamationmark.triangle", description: Text("This photo couldn't be loaded. It may have been deleted."))
            }
        }
        .navigationTitle(item.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
