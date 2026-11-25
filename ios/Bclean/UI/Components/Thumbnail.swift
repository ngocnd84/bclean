import Photos
import SwiftUI

final class ImageLoader {
    static let shared = ImageLoader()
    private let manager = PHCachingImageManager()

    func image(for asset: PHAsset,
               side: CGFloat,
               contentMode: PHImageContentMode = .aspectFill,
               allowNetwork: Bool = false) async -> UIImage? {
        let scale = UITraitCollection.current.displayScale > 0 ? UITraitCollection.current.displayScale : 2
        let target = CGSize(width: side * scale, height: side * scale)
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = allowNetwork
        return await withCheckedContinuation { cont in
            var resumed = false
            manager.requestImage(for: asset, targetSize: target, contentMode: contentMode, options: opts) { image, _ in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: image)
            }
        }
    }
}

struct ThumbnailView: View {
    let asset: PHAsset
    var side: CGFloat = 120
    var fit = false
    var allowNetwork = false
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipped()
        .task(id: asset.localIdentifier) {
            image = await ImageLoader.shared.image(for: asset,
                                                   side: side,
                                                   contentMode: fit ? .aspectFit : .aspectFill,
                                                   allowNetwork: allowNetwork)
        }
    }
}

/// Ô vuông trong lưới, có dấu chọn, nhãn video/dung lượng
struct MediaCell: View {
    let item: MediaItem
    let selected: Bool
    var badge: String? = nil
    var showSize = true

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(ThumbnailView(asset: item.asset, side: 140))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selected ? Theme.danger : Color.black.opacity(0.25))
                    .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.teal, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 4) {
                    if item.isVideo {
                        Image(systemName: "play.fill")
                        Text(Fmt.duration(item.asset.duration))
                    }
                    Spacer(minLength: 0)
                    if showSize && item.bytes > 0 { Text(Fmt.bytes(item.bytes)) }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(6)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Theme.danger : .clear, lineWidth: 3)
            }
            .contentShape(Rectangle())
    }
}

/// Xem ảnh/video lớn khi nhấn giữ
struct AssetPreview: View {
    let item: MediaItem

    var body: some View {
        VStack(spacing: 8) {
            ThumbnailView(asset: item.asset, side: 420, fit: true, allowNetwork: true)
                .frame(width: 320, height: 420)
            Text("\(Fmt.date(item.creationDate)) · \(Fmt.bytes(item.bytes))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }
}
