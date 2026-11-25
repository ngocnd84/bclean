# Bclean — App dọn dung lượng iPhone (MVP v1.0)

App iOS gốc (SwiftUI, iOS 16+). Toàn bộ phân tích ảnh chạy trên máy, không cần server.

## Tính năng v1.0

| Nhóm | Làm gì | Công nghệ |
|---|---|---|
| Ảnh trùng | Gom bản sao giống hệt nhau, giữ 1 tấm | dHash 64-bit + multi-index |
| Ảnh giống nhau | Gom ảnh chụp liên tiếp, tự chọn tấm đẹp nhất | Apple Vision feature print |
| Ảnh chụp màn hình | Liệt kê để xoá hàng loạt | PhotoKit |
| Ảnh mờ | Phát hiện ảnh nhoè/rung tay | Phương sai Laplacian |
| Video nặng | Sắp theo dung lượng, xoá hoặc **nén** (3 mức) | AVFoundation |
| Live Photo | Chuyển thành ảnh tĩnh, bỏ phần video | PhotoKit |
| Lướt ảnh | Vuốt trái xoá / phải giữ, theo từng tháng | SwiftUI |
| Mẹo | Hướng dẫn dọn "Đã xoá gần đây", Zalo, Tin nhắn... | — |
| Thu phí | Miễn phí 30 lượt xoá + 2 lượt nén mỗi ngày; Pro: tuần / năm / trọn đời | StoreKit 2 |
| Ngôn ngữ | Tiếng Việt + English (theo ngôn ngữ máy) | .strings |

## Chạy thử trên MacBook (khoảng 15 phút)

1. Cài **Xcode** từ Mac App Store (miễn phí, ~10 GB).
2. Giải nén `Bclean.zip`, mở Terminal, gõ:
   ```bash
   cd ~/Downloads/Bclean
   bash setup.sh
   ```
   Script tự cài XcodeGen (cần Homebrew), tạo `Bclean.xcodeproj` và mở Xcode.
3. Trong Xcode: chọn target **Bclean** → tab **Signing & Capabilities** → chọn **Team** (tài khoản Apple Developer của công ty).
4. Cắm iPhone vào Mac → chọn iPhone ở thanh trên cùng → bấm ▶︎ (Run).
   - Lần đầu: trên iPhone vào *Cài đặt > Cài đặt chung > Quản lý VPN & Thiết bị* → tin cậy nhà phát triển. Bật *Chế độ nhà phát triển* nếu được hỏi.
5. Thanh toán thử: khi chạy từ Xcode, app dùng file `StoreKit/Bclean.storekit` (giả lập, không mất tiền).
   Trong *Cài đặt > Developer (DEBUG)* của app có công tắc "Giả lập đã mua Pro".

> Nên test trên **máy thật** có nhiều ảnh. Simulator có rất ít ảnh nên không thấy được hiệu quả.

## Trước khi nộp App Store — checklist

**Tài sản đứng tên công ty (bắt buộc):**
- [ ] Tài khoản Apple Developer **Organization** đứng tên Công ty CP Bentic Việt Nam (99 USD/năm, cần số D-U-N-S).
- [ ] Repo code trong GitHub Organization của công ty, Ngọc là Owner.
- [ ] Domain `bclean.vn` (hoặc domain khác) đứng tên công ty; có trang Privacy + Terms + email hỗ trợ.

**Sửa trong code (`Bclean/App/AppConfig.swift`):**
- [ ] `termsURL`, `privacyURL`, `supportEmail` → link thật.
- [ ] `appStoreID` → ID app sau khi tạo trên App Store Connect.
- [ ] Nếu đổi bundle ID: sửa `PRODUCT_BUNDLE_IDENTIFIER` trong `project.yml` và 3 product ID.

**App Store Connect:**
- [ ] Tạo app, bundle ID `vn.bentic.bclean`.
- [ ] Tạo Subscription Group "Bclean Pro" gồm:
  - `vn.bentic.bclean.yearly` — 1 năm (gợi ý 24,99 USD; VN: 499.000đ)
  - `vn.bentic.bclean.weekly` — 1 tuần, dùng thử 3 ngày (gợi ý 3,99 USD; VN: 79.000đ)
- [ ] Tạo Non-Consumable `vn.bentic.bclean.lifetime` (gợi ý 34,99 USD; VN: 799.000đ).
- [ ] Điền Paid Apps Agreement + thông tin ngân hàng + thuế (không có thì không bán được).
- [ ] App Privacy: chọn "Data Not Collected" (app không thu thập dữ liệu cá nhân).
- [ ] Ảnh chụp màn hình thật của app (KHÔNG ghép ảnh "tăng tốc", "làm mát máy" — Apple từ chối).

**Lưu ý duyệt app (đọc kỹ):**
- Không hứa "xoá rác hệ thống", "tăng tốc", "dọn cache app khác", "làm mát pin" — iOS không cho phép, Apple sẽ từ chối (guideline 2.3 / 1.1.6).
- Paywall phải hiện rõ giá, chu kỳ, nút đóng, khôi phục giao dịch, link điều khoản — đã có sẵn.
- Danh mục "cleaner" đã bão hoà → mô tả App Store phải nêu điểm khác biệt (tiếng Việt, xử lý trên máy, gói miễn phí hào phóng, mẹo dọn Zalo).

## Tinh chỉnh độ chính xác

Tất cả ngưỡng nằm trong `AppConfig.swift`:
- `similarThresholdRev2` (iOS 17+): tăng → gom nhiều ảnh hơn (dễ nhầm), giảm → khắt khe hơn.
- `similarTimeWindow`: khoảng cách thời gian tối đa giữa 2 ảnh "giống nhau" (mặc định 90 giây).
- `blurThreshold`: tăng → nhiều ảnh bị coi là mờ hơn.
- `freeDeletesPerDay`, `freeCompressPerDay`: hạn mức miễn phí.

Cần test với 3–5 thư viện ảnh thật (≥ 5.000 ảnh) để chốt ngưỡng.

## Cấu trúc code

```
Bclean/
├─ App/          Điểm khởi động, cấu hình, theme, analytics
├─ Core/         Quét thư viện, thuật toán, xoá/nén/chuyển Live Photo
├─ Store/        Thanh toán StoreKit 2
├─ UI/           Giao diện (Dashboard, Lướt ảnh, Video, Cài đặt, Paywall)
└─ Resources/    Icon, màu, chuỗi vi/en, Privacy Manifest
BcleanTests/     Unit test cho thuật toán và hạn mức miễn phí
StoreKit/        Cấu hình thanh toán giả lập để test
```

## Việc để phase sau (chưa có trong v1.0)

Gộp danh bạ trùng · Dọn lịch cũ · Thư mục bí mật (khoá Face ID) · Widget dung lượng · Nhắc dọn định kỳ (notification) · Phân tích AI nâng cao (ảnh tài liệu, hoá đơn, meme) · Bản Android.
