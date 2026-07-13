# FormulaDoc

**Trình xem & chỉnh sửa Word, PDF, Excel trên Android — hiển thị đúng công
thức toán/hoá mà các app khác thường bỏ qua hoặc hiện lỗi.**

Ứng dụng Flutter chạy hoàn toàn offline, không có backend, không thu thập
dữ liệu người dùng.

---

## Vì sao có FormulaDoc

Hầu hết trình xem DOCX trên di động render sai hoặc bỏ qua hoàn toàn công
thức toán học — kể cả những công thức tạo bằng MathType/Equation Editor cũ
(vẫn cực kỳ phổ biến trong đề thi, tài liệu học thuật tiếng Việt). FormulaDoc
giải quyết đúng vấn đề đó bằng 2 pipeline riêng biệt:

| Loại công thức | Cách xử lý |
|---|---|
| OMML hiện đại (`<m:oMath>`, Word 2007+) | Parse trực tiếp sang LaTeX, hiển thị qua flutter_math_fork/KaTeX |
| MathType/Equation Editor cũ (ảnh WMF nhúng) | Renderer WMF viết riêng bằng Kotlin/Canvas — parse từng GDI record (font, pen, text run) và vẽ lại thành PNG, vì Android không có decoder WMF sẵn |

## Tính năng

**Xem tài liệu**
- Word (.docx), PDF (.pdf), Excel (.xlsx)
- Công thức toán (OMML + WMF/MathType), bảng biểu (kể cả merged cell), ảnh, hyperlink
- Zoom mượt (pinch + double-tap reset), bôi đen/copy văn bản
- 4 chế độ đọc: Sáng / Sepia / Tối / Tương phản cao
- Cỡ chữ, giãn dòng, lề tuỳ chỉnh
- Mục lục tự động từ heading, đánh dấu trang (bookmark)
- Tìm kiếm trong tài liệu (phân biệt hoa/thường, toàn từ) + tìm xuyên lịch sử
- Đọc to bằng giọng nói (TTS tiếng Việt)
- Tự động nhớ vị trí đọc dở, kể cả với PDF (theo số trang)

**Chỉnh sửa**
- DOCX: đổi Đậm/Nghiêng/Gạch chân, gõ chữ trực tiếp (đoạn văn 1 định dạng)
- XLSX: sửa giá trị từng ô, lưu lại không ảnh hưởng sheet/ô khác
- Tự động backup phiên bản trước mỗi lần lưu, khôi phục được khi cần

**Quản lý file**
- Lịch sử mở gần đây, yêu thích, bộ sưu tập (gắn nhãn theo chủ đề)
- Xoá hàng loạt, mở bằng file manager/Gmail/Drive ("Open with")
- Shortcut giữ icon app: mở file gần nhất / chọn file nhanh
- Thống kê đọc cá nhân (thời gian đọc, streak ngày liên tiếp)

**Khác**
- Chia sẻ file qua share sheet hệ thống
- In trực tiếp file PDF

## Không hỗ trợ (biết trước, có lý do)

- **PowerPoint (.pptx)** — chưa implement
- **Mục lục nhúng sẵn trong PDF** (PDF outline/bookmark) — package `pdfx`
  đang dùng không expose API đọc outline; cần đổi sang `pdfrx` hoặc thêm
  native PDFium binding mới làm được, chưa làm vì rủi ro build cao
- **Gõ chữ trực tiếp cho đoạn văn có nhiều định dạng khác nhau trong cùng
  câu** — chỉ đổi được style qua bôi đen. Lý do: thuật toán diff chính xác
  cho nhiều run cùng lúc rủi ro làm hỏng nội dung thật khi lưu, nên cố tình
  giới hạn ở trường hợp an toàn (đoạn 1 định dạng)
- **In DOCX/XLSX** — chỉ PDF in được (dùng thẳng byte gốc); DOCX/XLSX cần
  layout lại chính xác thành PDF phân trang, việc lớn hơn nhiều

## Kiến trúc

```
File (bytes)
     │
     ▼
DocumentParserRegistry        ← tự chọn parser theo định dạng
     │
     ├── DocxParser    (chạy trong compute() isolate, không block UI)
     ├── PdfParser     (đọc qua pdfx, native PdfRenderer)
     └── XlsxParser    (tự parse ZIP+XML, không phụ thuộc package ngoài)
     │
     ▼
DocumentModel                 ← Dart thuần, an toàn isolate
  blocks: List<DocumentBlock> ← sealed class
  images: Map<String, Uint8List>
     │
     ▼
DocumentRendererWidget
  switch (block) {
    ParagraphBlock     → ParagraphRenderer
    HeadingBlock       → HeadingRenderer
    EquationBlock      → EquationRenderer (LaTeX/KaTeX)
    ImageBlock         → Image.memory (WMF đã convert sẵn sang PNG)
    TableBlock         → grid có normalize merged-cell
    PdfDocumentBlock   → PdfView (pdfx)
    SpreadsheetBlock   → grid editable
  }
```

### WMF equation renderer (native Kotlin)

Phần khó nhất của dự án. `WmfRenderer.kt` tự parse binary WMF — đọc placeable
header lấy bounding box, loop qua GDI record (`CREATEFONTINDIRECT`,
`SELECTOBJECT`, `EXTTEXTOUT` kèm mảng `dx[]` để canh khoảng cách ký tự chính
xác từng chữ), vẽ lại bằng Android `Canvas`. Vài điểm quan trọng đã fix được
qua thực tế:

- **Object table phải dùng slot thấp nhất còn trống** (theo đúng WMF spec),
  không phải tăng dần tuần tự — sai chỗ này làm Symbol font và Times New
  Roman bị hoán đổi cho nhau
- **Bitmap phải cộng thêm padding bằng chiều cao font lớn nhất** — nếu không,
  chữ ở gần đáy công thức bị cắt mất phần dưới
- **Bảng map Symbol font → Unicode** phải đủ range `0xE6–0xF1` — đây là các
  ký tự vẽ ngoặc nhọn nhiều dòng (`⎧⎨⎩`) dùng trong công thức cấu tạo hoá học,
  thiếu sẽ hiện dấu `?`

Kết quả PNG được cache lại trong `DocumentModel.images`, render qua
`Image.memory()` như ảnh thường — không cần sửa gì ở tầng renderer.

## Cấu trúc thư mục

```
lib/
├── core/                  constants, exceptions, logger, file utils
├── data/
│   ├── models/            DocumentBlock (sealed), DocumentModel,
│   │                      FileRecord, DocumentEdit, EditHistory
│   ├── parsers/
│   │   ├── docx/          DocxParser + extractor/style/numbering/drawing
│   │   ├── omml/          OMML → LaTeX (200+ symbol mapping)
│   │   ├── pdf/           PdfParser (pdfx)
│   │   └── xlsx/          XlsxParser (tự parse ZIP+XML)
│   ├── repositories/      HistoryRepository (SharedPreferences)
│   └── serializers/       DocxSerializer, XlsxSerializer (ghi ngược file)
├── domain/                abstractions (DocumentSource, ParserInterface),
│                          CloudProvider (sẵn interface, chưa implement)
├── services/               FileService, HistoryService, DocumentSearchService,
│                          DocumentCacheService, HyperlinkService,
│                          ReadingStatsService, VersionHistoryService
├── platform/               PlatformIntentHandler (Open with),
│                          ShortcutService, WmfRenderService (channel → Kotlin)
└── presentation/
    ├── providers/          Riverpod: document/search/history/editor/
    │                      font_size/reading_prefs/theme/shortcut
    ├── renderers/           DocumentRendererWidget + renderer từng block
    └── screens/             home/ viewer/ editor/ settings/

android/app/src/main/kotlin/com/formuladoc/app/
├── MainActivity.kt        MethodChannel: WMF render + shortcut relay
└── WmfRenderer.kt         Parser + renderer WMF binary → PNG
```

## Bắt đầu

```bash
flutter --version        # đã test với Flutter stable, Dart >=3.4.0

cd formuladoc
flutter pub get

flutter run                        # chạy trên máy/emulator đã kết nối
flutter build apk --release        # build APK (cài trực tiếp / APKPure)
flutter build appbundle --release  # build AAB (bắt buộc cho CH Play)
```

### Build release cần chữ ký thật

Mặc định build release dùng debug key (chỉ để test local). Trước khi phát
hành, làm theo `android/KEYSTORE_SETUP.md` để tạo keystore thật — không có
bước này, Google Play sẽ từ chối file, và người dùng APKPure sẽ gặp lỗi
"signature mismatch" ở lần cập nhật tiếp theo nếu bạn đổi key giữa chừng.

### CI/CD

`.github/workflows/build-apk.yml` tự build cả APK và AAB mỗi khi push, tự
giải mã signing key từ GitHub Secrets nếu đã cấu hình (xem
`KEYSTORE_SETUP.md`), fallback về debug key nếu chưa — không phá build của
người khác chưa setup signing.

**Minification (R8) đang tắt cố ý** — không phải quên. R8 lỗi thường biểu
hiện thành crash lúc chạy thật chứ không phải lỗi build, nên "build xanh"
không đảm bảo an toàn. Cần test trên thiết bị thật trước khi bật
`minifyEnabled`/`shrinkResources` trong `android/app/build.gradle`.

## Quyền riêng tư

Không thu thập dữ liệu, không có analytics, không có backend. Toàn bộ lịch
sử/yêu thích/thống kê chỉ lưu local trên máy, mất khi gỡ app. Chi tiết đầy
đủ ở `docs/privacy-policy.html` (bật GitHub Pages để có URL public nộp cho
Play Console/APKPure).

## License

MIT.
