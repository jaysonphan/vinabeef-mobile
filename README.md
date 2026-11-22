# VinaBeef M2 – Mobile Field Health Recording (Flutter)

Owner: Thông (THONG-02 → THONG-05). Main module của M2: BS quét RFID tại chuồng → xác nhận đúng bò →
nhập vaccination/health → **lưu bền trên máy** → đồng bộ **cùng intentId** → server kiểm tra quyền/custody
hiện tại → app hiển thị ACCEPTED / REJECTED / NEEDS_REVIEW và lịch sử.

## Hai chế độ chạy

| Mode | Auth | Health API | Dùng khi |
|---|---|---|---|
| **Demo** | user giả lập `bs.demo`/`bs-local`, `fm.demo`/`fm-local` (giống realm Keycloak) | Máy chủ giả lập **trong app** (`data/simulator/`), DB riêng `vinabeef_simulator.db`; cùng seed, mã lỗi và luật như herd-health | Demo không cần Docker; diễn tập lỗi (mất mạng, mất response, thu hồi quyền) |
| **Live** | Keycloak, Authorization Code + PKCE, client public `vinabeef-mobile` | `herd-health` qua `http://localhost:8080` (JWT, current grants, Postgres) | Demo end-to-end thật: app → API → DB → history |

Demo mode **không** phải bằng chứng cho backend thật: bằng chứng server lấy từ Live mode và test của herd-health.

Dữ liệu seed (herd-health `V2__health_demo_seed.sql`; simulator dùng y hệt + 2 con demo-only):

| RFID | Bò | Vị trí | Ghi chú |
|---|---|---|---|
| `RFID-DL-1001` | Cow DL 1001 | FARM-DL / BARN-DL-01 | có lịch `FMD-BOOSTER` (scheduleId `20000000-…-0001`) |
| `RFID-DL-1002` | Cow DL 1002 | FARM-DL / BARN-DL-02 | ngoài phạm vi `bs.demo`, trong phạm vi `fm.demo` |
| `RFID-GL-2001` | Cow GL 2001 | FARM-GL / BARN-GL-01 | ngoài phạm vi cả hai user |
| `RFID-UNKNOWN-99` | – | – | tag chưa xác minh, không bao giờ trả về |
| `RFID-DL-1011`, `RFID-DL-1012` | Cow DL 1011/1012 | FARM-DL / BARN-DL-01 | **chỉ có ở simulator** (1011 có lịch `LSD`) |

Quyền (current grants, file `authorization-grants.demo.json`): `bs.demo` = BS ở BARN-DL-01; `fm.demo` = FM toàn FARM-DL.

## Chạy lần đầu

Cần Flutter ≥ 3.35 (nhóm pin 3.35.7 trong `.fvmrc`). Kiểm tra bằng `flutter doctor`.

### iOS (macOS + Xcode)

Cài một lần:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS        # nếu chưa có iOS Simulator runtime
brew install cocoapods
flutter precache --ios                  # tải Flutter.xcframework (thiếu thì pod install lỗi)
```

Sinh project iOS và chạy:

```bash
cd vinabeef-mobile
./scripts/bootstrap.sh ios      # flutter create (chỉ sinh file thiếu), patch Info.plist, pub get, pod install
flutter test
open -a Simulator
flutter run                     # chọn iPhone simulator nếu được hỏi
```

Chạy bằng Xcode: `open ios/Runner.xcworkspace` (mở **.xcworkspace**, không mở .xcodeproj), chọn scheme **Runner** và một
iPhone simulator, rồi bấm **▶ Run**. Code Dart vẫn sửa trong `lib/`; nếu Xcode chạy bản cũ, chạy
`flutter build ios --debug --simulator` rồi bấm Run lại.

`bootstrap.sh ios` thêm vào `ios/Runner/Info.plist`:
- `CFBundleURLTypes` → scheme `vn.edu.hcmut.vinabeef` (redirect đăng nhập Keycloak)
- `NSAppTransportSecurity/NSAllowsLocalNetworking = true` (gọi HTTP tới localhost). **Chỉ cho local dev**: xoá khi dùng HTTPS/release.

### Android

```bash
flutter doctor --android-licenses       # một lần
./scripts/bootstrap.sh android          # hoặc không tham số = android + ios
flutter test
flutter run                             # mở emulator trong Android Studio trước
```

Nếu script không patch được `android/app/build.gradle.kts`, thêm tay trong `defaultConfig { … }`:
`manifestPlaceholders["appAuthRedirectScheme"] = "vn.edu.hcmut.vinabeef"`.
Cleartext HTTP chỉ bật ở **debug** (`android/app/src/debug/…/network_security_config.xml`) cho localhost/10.0.2.2.

### Live mode với stack Docker

```bash
cd ../vinabeef && cp -n .env.example .env && ./dev up -Profile local
```

- **iOS Simulator**: dùng chung mạng với Mac, `localhost:8080/8081` gọi thẳng được – không cần thêm gì.
- **Android emulator**: `adb reverse tcp:8080 tcp:8080 && adb reverse tcp:8081 tcp:8081` (chạy lại mỗi lần emulator khởi động).
- **Máy thật**: `localhost` là chính điện thoại → dùng IP của máy chạy backend
  (`--dart-define=VB_API_BASE_URL=http://<IP>:8080`) và issuer Keycloak phải khớp; nên demo Live bằng simulator.

Trong app: chọn **Live** → *Sign in with Keycloak* (`bs.demo` / `bs-local`) → *Prepare session* (gọi
`GET /api/v1/cattle/in-scope`) → quét `RFID-DL-1001` → ghi FMD-BOOSTER theo lịch → **Accepted by server**.

Yêu cầu phía backend (đã cấu hình sẵn trong `vinabeef/compose.yaml`):
- `HEALTH_GRANTS_FIXTURE_ENABLED=true` (mặc định) – current grants đọc từ JSON fixture vì IAM của Phú chưa có.
  Đặt `false` thì mọi API trả **503** (fail closed).
- herd-health xác thực JWT: `iss` phải là `http://localhost:8081/realms/vinabeef`, principal = `preferred_username`.
- Muốn reset dữ liệu server: `cd ../vinabeef && ./dev reset -Profile local -Force && ./dev up -Profile local`.

Kiểm tra nhanh bằng curl (client `vinabeef-dev-cli` chỉ dành cho smoke test):
```bash
TOKEN=$(curl -s -d grant_type=password -d client_id=vinabeef-dev-cli -d username=bs.demo -d password=bs-local \
  http://localhost:8081/realms/vinabeef/protocol/openid-connect/token | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/cattle/in-scope
```

Override khác: `--dart-define=VB_OIDC_ISSUER=…`, `--dart-define=VB_OIDC_CLIENT_ID=…`.

### Dừng / reset

| Muốn | Cách |
|---|---|
| Dừng `flutter run` | bấm `q` (hoặc Ctrl+C). `r` = hot reload, `R` = restart |
| Dừng khi chạy từ Xcode | nút ■ Stop hoặc Cmd + . |
| Tắt simulator | Cmd + Q, hoặc `xcrun simctl shutdown all` |
| Dừng backend (giữ dữ liệu) | `cd ../vinabeef && ./dev down` |
| Xoá dữ liệu app để demo lại từ đầu | giữ icon app trên simulator → **Remove App** (Android: gỡ app / Wipe Data) |

Dừng app không mất dữ liệu: draft/pending nằm trong SQLite của app.

### Lỗi thường gặp

| Lỗi | Cách xử lý |
|---|---|
| `Flutter.xcframework must exist` khi `pod install` | `flutter precache --ios` rồi `cd ios && pod install` |
| `requires a higher minimum iOS deployment target` | `ios/Podfile`: dòng `platform :ios, '13.0'` không bị comment, rồi `pod install` |
| Xcode yêu cầu Signing | Runner → *Signing & Capabilities* → chọn Team (máy iPhone thật mới cần) |
| `No devices found` | mở Simulator / Android emulator trước, kiểm tra `flutter devices` |
| Live không kết nối được (Android) | chạy lại `adb reverse` |

## Kịch bản demo (Demo mode)

### Luồng demo chính (5 phút)

1. `flutter run` → màn đăng nhập chọn **Demo**, đăng nhập `bs.demo` / `bs-local`.
2. Bấm **Prepare session (needs network)** → tải các con bò BARN-DL-01 (simulator: 3 con, Live: 1 con), hạn 12h.
3. Bấm **Scan RFID** → bấm chip `RFID-DL-1001` (đầu đọc giả lập) → **This is the animal**.
4. Chọn lịch *FMD-BOOSTER* → **Review & confirm** → tick *I confirm this is…* → **Confirm**.
5. Ghi nhận hiện **Pending sync** rồi **Accepted by server** (có mã hồ sơ server). Bấm vào ghi nhận → **History of this animal**.
6. Mở thẻ **Simulated server** và chạy các kịch bản lỗi theo bảng dưới.

Lưu ý khi demo: quét RFID hiện dùng **đầu đọc giả lập** (chưa có phần cứng/SDK). NFC điện thoại (13.56 MHz) không đọc
được thẻ tai bò chuẩn ISO 11784/11785 (134.2 kHz); thực tế dùng đầu đọc gậy Bluetooth nối với điện thoại.

Màn hình chính có thẻ **"Simulated server"** để bật/tắt lỗi. Đếm *hồ sơ/receipt trên server* để thấy không có bản trùng.

| Test (plan 7.2) | Thao tác | Kết quả mong đợi (Demo = Live) |
|---|---|---|
| Thin slice | *Prepare session* → quét `RFID-DL-1001` → lịch FMD-BOOSTER → xác nhận | "Pending sync" → "Accepted by server"; *History* hiện hồ sơ |
| T05 offline + restart | Turn off *Phone ↔ server network* → ghi cho **các con khác nhau** (`RFID-DL-1001`, `1011`, `1012`) → **kill app** → mở lại → đăng nhập lại (token demo chỉ ở RAM; mạng giả lập về BẬT) → Sync | Intent còn nguyên sau restart; mỗi intent ACCEPTED đúng 1 lần, số hồ sơ server tăng đúng số intent |
| T05b 2 bản offline cùng 1 con | Tắt mạng → ghi 2 bản cho `RFID-DL-1012` → bật mạng | Bản 1 ACCEPTED; bản 2 **NEEDS_REVIEW `RESOURCE_VERSION_CHANGED`** (server dùng resourceVersion của bò làm optimistic lock) |
| T06 response lost | Bật *Lose the next response* → xác nhận 1 bản | Lần 1: PENDING "outcome unknown". Lần sau app hỏi receipt trước → ACCEPTED, server chỉ 1 hồ sơ |
| T07 quyền | *Revoke access* rồi sync / quét *Out-of-scope animal* (`RFID-DL-1002`) / *Expire token* | REJECTED `ACCESS_DENIED` / không ghi được (không có trong phiên) / banner "Sign in again", pending giữ nguyên |
| T09 nhiều tag, liều trùng | *2 tags at once*; *Unknown tag* (`RFID-UNKNOWN-99`); ghi 2 intent cùng lịch FMD-BOOSTER | Phải tự chọn bò; tag lạ không ghi được; intent thứ 2 → REJECTED `SCHEDULE_ALREADY_COMPLETED`, không thêm hồ sơ |
| Custody đổi trước sync | Tắt mạng → ghi cho `RFID-DL-1001` → *Move* Cow DL 1001 sang BARN-DL-02 → bật mạng | REJECTED `ACCESS_DENIED` (BS không còn quyền), draft/nội dung gốc giữ nguyên trên máy |

Mã lý do hiển thị kèm giải thích tiếng Việt (`reasonText` trong `widgets.dart`).

## Kiến trúc (map cho report – module view)

```
lib/
  core/                      config, canonical JSON, Clock
  composition_root.dart      nơi duy nhất biết adapter cụ thể (DIP) – Demo vs Live
  features/capture/
    domain/                  TagObservation, Cattle, LocalIntent + IntentStatus, SubmitResult, WorkSession
    application/             ports.dart, CaptureService, SyncCoordinator, WorkSessionService
    data/                    SqliteDraftStore, SqliteWorkSessionStore, HttpHealthApi, FakeTagReadSource,
                             simulator/ (SimulatedHealthBackend + SimulatedHealthApi)
    presentation/            OutboxController + các màn hình
  features/auth/             AuthSession port, KeycloakAuthSession, DemoAuthSession, SessionController, Login
```

| SOLID | Ở đâu trong code |
|---|---|
| SRP | `CaptureValidator` (luật form) ≠ `CaptureService` (tạo/khóa intent) ≠ `SyncCoordinator` (gửi/retry) ≠ adapter HTTP |
| OCP | Thêm reader thật = class mới implement `TagReadSource`; thêm backend = adapter mới cho ports; core không đổi |
| LSP | `HttpHealthApi` và `SimulatedHealthApi` cùng ngữ nghĩa: kết quả cuối = `SubmitResult`, lỗi tạm = `TransientSyncFailure(maybeDelivered)`, hết hạn = `AuthRequiredException` |
| ISP | `TagReadSource`, `HealthSubmitter`, `ReceiptReader`, `HistoryReader`, `CattleDirectory`, `DraftStore` tách theo client |
| DIP | `application/` chỉ import `ports.dart` + domain; Dio/sqflite/AppAuth chỉ xuất hiện trong `data/` và `composition_root.dart` |

### Các quy tắc đã cài (plan 4.3)

- Scan chỉ xác định bò; nhiều tag → bắt chọn; tag lạ/ngoài phạm vi → không ghi được. Form gắn cố định 1 con bò.
- `intentId` sinh khi user **xác nhận**; body canonical JSON lưu 1 lần (`submitted_body`), mọi retry gửi y nguyên. DB chặn sửa/xóa khi không còn DRAFT (guard trong `WHERE`).
- Body không chứa actor/role/farm – server lấy từ token. Có `occurredAt` (lúc tiêm thật) tách `capturedAt`/`committedAt`.
- Timeout sau khi gửi / 5xx → `outcomeUnknown`, lần sau GET receipt trước; 404 receipt mới POST lại.
- 401/hết token → giữ toàn bộ pending, yêu cầu đăng nhập lại. Đăng xuất giữ pending (theo owner), xóa cache bò.
- Ghi offline chỉ khi **phiên làm việc** (danh sách bò trong phạm vi, hạn 12h – giá trị đề xuất P) còn hạn và đúng user.
- Đồng bộ: khi mở app, mỗi 20s khi app mở, sau mỗi lần xác nhận, nút Sync / kéo để làm mới.

### Tích hợp với herd-health (`vinabeef/contracts/openapi/herd-health.v1.yaml`)

| App | Endpoint | Mapping |
|---|---|---|
| Chuẩn bị phiên | `GET /api/v1/cattle/in-scope` | `items[]` → cache bò + `openSchedules`; `resourceVersion` dùng làm `expectedVersion` |
| Gửi intent | `POST /api/v1/health-intents` | body `{intentId, cattleId, type, payload, occurredAt, deviceRef, expectedVersion, scheduleId?}` (server từ chối field lạ). `capturedAt`, `readerObservationId` nằm trong `payload` |
| Kết quả | 201/200 `HealthReceipt` | `status` ACCEPTED/NEEDS_REVIEW/REJECTED; ACCEPTED cập nhật `currentVersion` vào cache phiên |
| | 409 problem + `receipt` | theo `receipt.status` (vd. REJECTED `SCHEDULE_ALREADY_COMPLETED`, NEEDS_REVIEW `RESOURCE_VERSION_CHANGED`); không có receipt (`IDEMPOTENCY_KEY_REUSED`) → NEEDS_REVIEW |
| | 403 / 422 | REJECTED với `code` (`ACCESS_DENIED`, `INVALID_INPUT`) |
| | 401 | giữ pending, yêu cầu đăng nhập lại |
| | 503 / 5xx / timeout | giữ PENDING_SYNC; 5xx/timeout → lần sau hỏi receipt trước |
| Receipt | `GET /api/v1/health-intents/{id}` | 404 = server chưa thấy → gửi lại cùng body |
| Lịch sử | `GET /api/v1/cattle/{id}/health-history` | `records[]` (type, payload, recordedAt) |

## Giới hạn (ghi vào coverage/limitations)

- Chưa có phần cứng/SDK RFID: `FakeTagReadSource` chỉ kiểm contract phần mềm (TagObservation v1, readerKind MOBILE, không direction).
- Dùng **sqflite** thay drift (plan) để không cần build_runner/codegen; schema có version + `onUpgrade`.
- Không dùng `connectivity_plus`: trạng thái do server trả quyết định; sync foreground (không background WorkManager).
- Simulator là demo trong app, không chứng minh transaction/authorization của herd-health.
- Code được viết khi chưa chạy được `flutter analyze/test` trong môi trường sinh code → cần chạy `flutter test` và sửa nếu có lỗi trước code freeze.
- Server khoá lạc quan theo `resourceVersion` của bò: nhiều bản offline cho **cùng một con** thì từ bản thứ 2 trở đi là NEEDS_REVIEW – cần FM đối chiếu (đúng thiết kế herd-health, không phải lỗi app).
- Bò bị chuyển chuồng trước khi sync → herd-health trả 403 nên app hiện REJECTED `ACCESS_DENIED` (plan đề xuất NEEDS_REVIEW; cần nhóm chốt).
- Ghi nhận cũ tạo trước bản tích hợp (body cũ) sẽ bị REJECTED `INVALID_INPUT`; xoá app trên simulator để demo sạch.
- Logout Keycloak chỉ xóa token local (chưa gọi end-session).
