# Bclean — app dọn dung lượng điện thoại

| Nền tảng | Thư mục | Công nghệ | Trạng thái |
|---|---|---|---|
| iPhone | `ios/` | SwiftUI, iOS 16+ | Build + 6 unit test xanh trên CI (Xcode 16.4) |
| Android | `android/` | Kotlin + Jetpack Compose, Android 11+ | APK test build tự động, chạy thử trên máy ảo Android 14 |

## Tải bản test

- **Android:** https://github.com/ngocnd84/bclean/releases/tag/android-test (đăng nhập GitHub → tải file `.apk` → mở để cài).
- **iPhone:** xem mục "Bản test iPhone" bên dưới.

## Build tự động (GitHub Actions)

| Workflow | Khi nào chạy | Kết quả |
|---|---|---|
| `Android – build APK` | Mỗi lần sửa `android/` | APK test → Release `android-test` + ảnh chụp màn hình máy ảo |
| `iOS – build & test` | Mỗi lần sửa `ios/` | Biên dịch + unit test trên iPhone simulator |
| `iOS – TestFlight (chạy tay)` | Bấm "Run workflow" | Đẩy bản build lên TestFlight (cần 4 secrets, xem file workflow) |

## Bản test iPhone — 2 cách

**Cách 1 — Cắm cáp, miễn phí (chỉ máy của anh, hết hạn sau 7 ngày):**
MacBook cài Xcode → `cd ios && bash setup.sh` → chọn Team = Apple ID cá nhân → cắm iPhone → bấm ▶︎.

**Cách 2 — TestFlight (gửi link cho tối đa 10.000 người test):**
1. Đăng ký Apple Developer Program (99 USD/năm) — nên đứng tên công ty.
2. App Store Connect: tạo app bundle ID `vn.bentic.bclean`.
3. Users and Access → Integrations → tạo API key quyền **Admin**, tải file `.p8`.
4. Repo → Settings → Secrets and variables → Actions → thêm `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (lệnh: `base64 -i AuthKey_XXXX.p8`).
5. Actions → "iOS – TestFlight (chạy tay)" → Run workflow. 10–30 phút sau bản build có trong TestFlight.

## Khác biệt Android so với iPhone (bản test)

- Ảnh giống nhau dùng dHash (iPhone dùng Apple Vision chính xác hơn).
- Chưa có Live Photo (Android dùng Motion Photo — phase sau).
- Xoá trên Android là **xoá hẳn** sau khi hệ thống xác nhận (iPhone vào "Đã xoá gần đây" 30 ngày).
- Thanh toán Google Play **chưa bật**: bật "Giả lập đã mua Pro" trong Cài đặt để thử tính năng Pro.

Chi tiết từng nền tảng: `ios/README.md`.
