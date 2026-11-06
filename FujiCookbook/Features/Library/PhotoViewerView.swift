import SwiftUI

/// Full-screen, swipeable viewer for a recipe's sample photos. Each page pinch-zooms and pans
/// (see `ZoomableImage`) so grain and colour rendering can be inspected up close; double-tap
/// toggles a 2.5× close-up on the tapped spot.
struct PhotoViewerView: View {
    let photos: [RecipePhoto]
    @State var selection: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.element.uuid) { index, photo in
                    Group {
                        if let image = UIImage(data: photo.imageData) {
                            ZoomableImage(image: image)
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
