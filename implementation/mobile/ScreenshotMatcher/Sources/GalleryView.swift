import SwiftUI

struct GalleryView: View {
    @ObservedObject var store: GalleryStore
    let title: String
    let emptyIcon: String
    let emptyText: String

    @State private var isSelecting = false
    @State private var selection: Set<GalleryItem.ID> = []
    @State private var showDeleteConfirmation = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView(title, systemImage: emptyIcon, description: Text(emptyText))
                } else {
                    grid
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: GalleryItem.self) { item in
                ImageDetailView(store: store, item: item)
            }
            .toolbar { toolbarContent }
            .confirmationDialog(
                deletePrompt,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteSelected)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(store.items) { item in
                    thumbnailCell(for: item)
                }
            }
            .padding(2)
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionActionBar
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(for item: GalleryItem) -> some View {
        if isSelecting {
            Button {
                toggle(item)
            } label: {
                thumbnail(for: item)
                    .overlay(selectionOverlay(for: item))
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) {
                thumbnail(for: item)
            }
            .buttonStyle(.plain)
        }
    }

    private func thumbnail(for item: GalleryItem) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = store.image(for: item) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func selectionOverlay(for item: GalleryItem) -> some View {
        let selected = selection.contains(item.id)
        ZStack(alignment: .bottomTrailing) {
            if selected {
                Color.accentColor.opacity(0.25)
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.accentColor : .white)
                .background(Circle().fill(.black.opacity(0.25)))
                .padding(4)
        }
    }

    private var selectionActionBar: some View {
        HStack {
            let images = selectedImages
            if !images.isEmpty {
                ShareLink(items: images) { image in
                    SharePreview("Photo", image: image)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            } else {
                Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
            }

            Spacer()
            Text(selectionCountText).font(.subheadline)
            Spacer()

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selection.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if store.items.isEmpty {
                EmptyView()
            } else if isSelecting {
                Button("Done") {
                    isSelecting = false
                    selection.removeAll()
                }
            } else {
                Button("Select") { isSelecting = true }
            }
        }
    }

    private var selectedImages: [Image] {
        store.items
            .filter { selection.contains($0.id) }
            .compactMap { store.image(for: $0) }
            .map { Image(uiImage: $0) }
    }

    private var selectionCountText: String {
        switch selection.count {
        case 0: return "Select Items"
        case 1: return "1 Selected"
        default: return "\(selection.count) Selected"
        }
    }

    private var deletePrompt: String {
        selection.count == 1 ? "Delete this photo?" : "Delete \(selection.count) photos?"
    }

    private func toggle(_ item: GalleryItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    private func deleteSelected() {
        for item in store.items where selection.contains(item.id) {
            store.delete(item)
        }
        selection.removeAll()
        isSelecting = false
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ShareLink(
                                item: Image(uiImage: image),
                                preview: SharePreview("Photo", image: Image(uiImage: image))
                            )
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
            } else {
                ContentUnavailableView(
                    "Image unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This photo couldn't be loaded. It may have been deleted.")
                )
            }
        }
        .navigationTitle(item.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
