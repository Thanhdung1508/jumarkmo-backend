# Đọc code backend theo thứ tự

1. JuniorMarkApplication.kt: khởi động Spring Boot.
2. config/ApiRequestFilter.kt: giới hạn JSON và kiểm tra origin cho yêu cầu API.
3. auth/AuthController.kt: nhận yêu cầu đăng nhập; gọi AuthService.
4. auth/AuthService.kt: kiểm tra thông tin, băm/đối chiếu mật khẩu, tạo hoặc thu hồi phiên.
5. auth/AuthRepository.kt: câu SQL liên quan tài khoản.
6. data/DataController.kt → DataService.kt → DataRepository.kt: lưu hồ sơ, ghi chú, bộ sưu tập, đọc catalog.
7. database/Database.kt: mở transaction, bind tham số, gán auth.uid() và role để RLS giới hạn dữ liệu theo tài khoản.

Frontend gửi cookie HttpOnly tự động. Server chỉ lưu hash token; không gửi mật khẩu database ra trình duyệt. Với hai tài khoản khác nhau, RLS khiến tài khoản B không thấy ghi chú của A.

/data và /rpc là hợp đồng tương thích frontend hiện tại. Chỉ bảng/cột/hàm trong DataPolicy.kt được phép gọi; không phải SQL endpoint tự do.

SQL chỉ tồn tại ở database/. Migrations tạo bảng/ràng buộc/RLS, seed chứa nội dung ban đầu. Không copy SQL vào frontend hoặc resources.
