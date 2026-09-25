# JuniorMark — Kotlin Backend

Backend riêng của website, mở thư mục này bằng IntelliJ rồi chọn **Load Maven Project** từ pom.xml. Dùng JDK 17.

## Chạy

1. Chạy scripts/database.ps1 -Action start (máy mới dùng -Action create).
2. IntelliJ: Maven → Reload All Projects, mở src/main/kotlin/com/juniormark/JuniorMarkApplication.kt rồi Run main. Working directory là thư mục backend.
3. Hoặc terminal: ./scripts/run.ps1 -Task run. API tại http://127.0.0.1:3001/api/health.
4. Frontend ở C:/laragon/www/juniormark-frontend, chạy npm run dev. Mở http://127.0.0.1:5173.

## File SQL ở đâu?

- database/migrations/: schema, bảng, trigger, RLS; 007_local_auth.sql là bảng phiên và mật khẩu cho Kotlin.
- database/seed/catalog.sql: INSERT hồ sơ, ảnh, playlist, sự kiện, dự án và nội dung.
- database/local-bootstrap.sql: schema auth/storage tương thích trên PostgreSQL local trống. Không chạy trên Supabase cloud.

Database juniormark tại 127.0.0.1:55432, user postgres. Dữ liệu local nằm trong .local/postgres; file mật khẩu .local/postgres-password.local không đưa lên Git. Các file SQL trong database không chứa mật khẩu.

Đã có database thì không chạy lại toàn bộ migration. scripts/database.ps1 -Action create giữ nguyên database đã tồn tại. scripts/import-content.ps1 chỉ nhập nội dung chưa có; sửa nội dung đang tồn tại bằng UPDATE rồi tải lại web. API chỉ đọc nội dung published.

## Cấu trúc

- src/main/kotlin/com/juniormark/auth: đăng ký, đăng nhập, session, mật khẩu.
- src/main/kotlin/com/juniormark/data: hồ sơ, ghi chú, đã lưu và catalog.
- src/main/kotlin/com/juniormark/database: JDBC và transaction/RLS.
- src/main/kotlin/com/juniormark/config: datasource và kiểm tra HTTP.
- src/main/kotlin/com/juniormark/common: định dạng lỗi an toàn.
- src/test/kotlin: kiểm thử Kotlin, gồm test HTTP/database khi bật RUN_DATABASE_TESTS=true.
- docs/architecture.md: giải thích cách đọc code và luồng xử lý.

## Kiểm thử

./scripts/run.ps1 -Task test chạy test không cần database.
./scripts/run.ps1 -Task verify chạy thêm test HTTP với PostgreSQL đã bật; tạo hai tài khoản thử rồi xoá đúng dữ liệu test.
./scripts/run.ps1 -Task package tạo target/jumarkmo-backend-1.0.0.jar.

## Phạm vi hiện tại

Đây là backend phát triển local, cùng máy với frontend. Đăng ký chưa xác minh email; thư đặt lại mật khẩu ghi ở .local/mail (không gửi email thật). Không đưa cấu hình local lên Internet như bản production. Giữ hash scrypt tương thích với tài khoản cũ. Kotlin là backend duy nhất; không chạy server Node cũ.
