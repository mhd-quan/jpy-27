# Kiểm trên máy: bìa trang chủ fade và lặp vòng, quán ăn đủ ngày

Thay đổi nhỏ sau PR #11. Chưa bước nào được làm: code app chỉ được biên dịch trên CI, chưa chạy trên máy hay
simulator. Bản build: Release, mở từ màn hình chính, ngày trên máy trước 18/10/2027 (để tab Hôm nay là trang bìa).
Điền cột **Kết quả** (Đạt / Không đạt, kèm điều thấy được).

| # | Bước | Mong đợi | Kết quả |
| --- | --- | --- | --- |
| 1 | Mở tab Hôm nay, để yên trên ảnh bìa khoảng 15 giây. | Mỗi 6 giây ảnh đổi tại chỗ: ảnh kế mờ dần lên đè ảnh cũ trong khoảng 0,3 giây, không trượt ngang. Tên địa điểm và tác giả ảnh mờ ra rồi mờ vào cùng lúc; chấm trang dài ra ở chấm kế. Không rung. | |
| 2 | Vuốt ảnh bìa sang trái chậm, dừng giữa chừng, rồi thả. | Trong lúc vuốt ảnh không trượt: ảnh kế hiện dần theo ngón tay. Thả quá nửa thì sang ảnh kế, chưa tới nửa thì về ảnh cũ. Rung một nhịp khi sang ảnh khác. | |
| 3 | Vuốt sang phải (về ảnh trước) khi đang ở ảnh đầu (ngày 1, Kanda Myōjin). | Sang ảnh cuối (ngày 11, Hōzen-ji) bằng một lần mờ, không chạy ngược qua mọi ảnh. Chấm cuối sáng. | |
| 4 | Để bìa tự chuyển tới ảnh cuối, rồi chờ thêm một lần. | Sau ảnh cuối là ảnh đầu, bằng đúng một lần mờ, rồi bìa tiếp tục chuyển vòng mới. | |
| 5 | Chạm ảnh bìa của ngày 2 (Sensō-ji). Đóng trang. Làm lại với ngày 5 (cảng Shimizu). | Trang địa điểm mọc ra từ ảnh bìa và mở đúng bằng ảnh đó: lúc zoom ảnh không đổi sang ảnh khác. Ảnh thứ hai trở đi là ảnh cũ của địa điểm. Với Shimizu, ảnh bìa không lặp lại lần hai trong dãy. Đóng thì thu về đúng ảnh bìa. | |
| 6 | Chạm ảnh bìa ngay sau khi nó vừa tự chuyển, và ngay sau một lần vuốt. | Mở đúng địa điểm của ảnh đang hiện (đọc tên ở chân ảnh), không mở địa điểm của ảnh bên cạnh. | |
| 7 | Cuộn trang chủ xuống cho ảnh bìa khuất hẳn, chờ 10 giây, cuộn lên lại. | Ảnh bìa vẫn là ảnh lúc rời đi, không chớp ô xám, không nhảy. Bìa tự chuyển tiếp sau 6 giây. | |
| 8 | Bật Giảm chuyển động (Cài đặt iOS › Trợ năng › Chuyển động). Mở trang chủ, chờ 10 giây, rồi vuốt ảnh bìa. | Bìa không tự chuyển và không zoom chậm. Vuốt vẫn sang ảnh kế bằng một lần mờ. | |
| 9 | Tắt Giảm chuyển động. Bật Chế độ nguồn điện thấp, mở trang chủ. | Bìa không tự chuyển, không zoom chậm. Tắt nguồn điện thấp thì bìa chuyển tiếp. | |
| 10 | Bật VoiceOver, vuốt qua phần bìa. | VoiceOver đọc tên địa điểm của ảnh đang hiện một lần, không đọc lại các bản lặp của dải ảnh. | |
| 11 | Tab Lịch trình, gõ "Sensō" vào ô tìm. Chạm dòng Sensō-ji trong mục Địa điểm. | Ảnh nhỏ của dòng là ảnh bìa (ngũ trùng tháp về đêm), và trang mở bằng đúng ảnh đó. | |
| 12 | Cuộn tới mục "Quán ăn" trên trang chủ, vuốt hết dải. | Có quán của mọi ngày từ ngày 1 tới ngày 11 (27 quán), theo thứ tự ngày; thẻ cuối ghi "Ngày 11". | |
