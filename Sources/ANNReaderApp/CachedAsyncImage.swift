import SwiftUI

/// картинка через дисковый ImageCache (15 дней, офлайн) с плавным появлением;
/// интерфейс как у AsyncImage, placeholder получает флаг failed
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: (_ failed: Bool) -> Placeholder

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                content(Image(nsImage: image)).transition(.opacity)
            } else {
                placeholder(failed)
            }
        }
        .task(id: url) {
            failed = false
            image = nil
            if let data = await ImageCache.shared.data(for: url), let img = NSImage(data: data) {
                withAnimation(.easeOut(duration: 0.25)) { image = img }
            } else {
                failed = true
            }
        }
    }
}
