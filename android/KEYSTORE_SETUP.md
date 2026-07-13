# Thiết lập chữ ký release (bắt buộc trước khi phát hành app)

App hiện đang build release bằng **debug key**. Dù phát hành qua CH Play,
APKPure, hay cho tải trực tiếp — nơi nào cũng cần APK/AAB ký bằng key thật,
không nơi nào chấp nhận debug key. Ngoài ra, nếu đổi key giữa các lần cập
nhật, người dùng đã cài bản cũ sẽ gặp lỗi "signature mismatch" và phải gỡ
cài lại — nên **key này chỉ tạo một lần và dùng mãi mãi** cho toàn bộ vòng
đời của app.

⚠️ **Không bao giờ commit file `.jks` hoặc `key.properties` thật lên Git.**
Mất file `.jks` hoặc quên mật khẩu = không thể cập nhật app đó nữa vĩnh viễn
(phải tạo app mới, mất hết review/rating/số lượt tải cũ).
**Hãy backup file `.jks` ở nơi an toàn (không phải trong repo) ngay sau khi tạo.**

## Bước 1 — Tạo keystore

Chạy lệnh này trên máy (cần có JDK, `keytool` đi kèm sẵn):

```bash
keytool -genkey -v -keystore ~/formuladoc-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias formuladoc
```

Lệnh sẽ hỏi vài thông tin (tên, tổ chức, quốc gia — điền gì cũng được, không
ảnh hưởng chức năng) và **2 mật khẩu** (keystore password + key password) —
ghi nhớ hoặc lưu vào password manager, không lưu trong file text thường.

Lưu ý: file được tạo ở `~/formuladoc-release-key.jks` — **ngoài** thư mục
repo, để không có nguy cơ commit nhầm.

## Bước 2 — Tạo `key.properties`

```bash
cp android/key.properties.example android/key.properties
```

Sửa `android/key.properties` với giá trị thật:

```properties
storeFile=/home/ten-ban/formuladoc-release-key.jks
storePassword=<mật khẩu keystore ở bước 1>
keyAlias=formuladoc
keyPassword=<mật khẩu key ở bước 1>
```

Dùng **đường dẫn tuyệt đối** tới file `.jks` (không phải đường dẫn tương đối)
để tránh nhầm lẫn dù bạn chạy build từ đâu.

File `android/key.properties` đã được thêm vào `.gitignore` — sẽ không bị
commit nhầm.

## Bước 3 — Build thử

```bash
flutter build apk --release         # file để up APKPure / cài trực tiếp
flutter build appbundle --release   # file để up Google Play (nếu cần)
```

Nếu thấy dòng cảnh báo "key.properties not found" biến mất và build ra file
`build/app/outputs/flutter-apk/app-release.apk` — vậy là đã ký đúng. Đây là
file bạn upload lên APKPure.

## Bước 4 — Ký trên GitHub Actions (CI)

Repo build qua GitHub Actions, nên CI cũng cần key để build. Không đẩy file
`.jks` lên GitHub — encode base64 rồi lưu vào **GitHub Secrets**:

```bash
base64 -i ~/formuladoc-release-key.jks -o keystore_base64.txt
```

Vào GitHub repo → **Settings → Secrets and variables → Actions** → tạo 4 secret:

| Tên secret | Giá trị |
|---|---|
| `KEYSTORE_BASE64` | nội dung file `keystore_base64.txt` |
| `KEYSTORE_PASSWORD` | mật khẩu keystore |
| `KEY_ALIAS` | `formuladoc` |
| `KEY_PASSWORD` | mật khẩu key |

Workflow `.github/workflows/build-apk.yml` đã được cập nhật để tự giải mã
các secret này thành `key.properties` + file `.jks` ngay trong CI trước khi
build — không cần làm gì thêm sau khi set 4 secret ở trên.

Sau khi set xong, xoá file `keystore_base64.txt` (chỉ cần dùng 1 lần):
```bash
rm keystore_base64.txt
```
