# Prompt cho agent nhận Phase 4–5

Dán nguyên phần dưới vạch vào một phiên mới, mở trên repo `mhd-quan/jpy-27`, nhánh gốc `main`.

---

Bạn là controller cho Phase 4 (chokepoint) và Phase 5 (mở/thu mượt) của kế hoạch iOS JP27. Lượt trước
đã làm xong và merge Phase 0–3. Bạn chạy theo `superpowers:subagent-driven-development`: bạn điều phối,
subagent implementer và reviewer làm việc, bạn ra ruling và ghi ledger. Trả lời tôi bằng tiếng Việt.

**Đọc trước khi làm bất cứ gì:** `docs/superpowers/handoffs/2026-11-04-phase-4-5/README.md`. Nó là bối
cảnh đầy đủ:
- trạng thái và môi trường;
- quy trình lượt trước đã dùng, và các bài học;
- thứ tự việc, bậc và effort đề xuất;
- chín xung đột P1–P9 tìm được khi quét plan;
- các quy tắc không được phá;
- bộ đồ nghề.

Đọc tiếp các tài liệu nó liệt kê ở § 0, theo đúng thứ tự.

## Thiết lập

1. Gọi skill `superpowers:subagent-driven-development`, rồi tạo workspace của plan
   `docs/superpowers/plans/2026-11-03-ios-hardening-and-smoothness.md`.
2. Chép `docs/superpowers/handoffs/2026-11-04-phase-4-5/kit/` vào workspace và sửa đường dẫn cũ. Chép `interfaces-phase0-3.md` thành `interfaces.md`.
3. Tạo ledger mới. Ghi các dòng `Task <N>: complete — see docs/superpowers/reports/2026-11-04-phases-0-3-report.md` như README § 7 hướng dẫn.
4. Viết hợp đồng `docs/superpowers/plans/2026-11-04-execution-contract-phase4-5.md` theo README § 5.
5. Quét plan theo skill. Ra ruling cho P1–P9 (đồng ý với đề xuất trong README hoặc ruling khác, kèm lý do và giá phải trả nếu sai), và ghi vào ledger.
6. ST-1: chạy `swift test`, `node --test 'scripts/*.test.mjs'` và `node scripts/lint-saves.mjs` trên `main`. Xác nhận CI "App builds" xanh, 0 warning ở commit gốc.

## Thứ tự việc

1. **Bước 0** (README § 4): New-1, New-2, M3; New-3 và nit `.ack` nếu rẻ.
   - Mỗi sửa có test TripKit viết RED trước, qua review, CI xanh, 0 warning.
   - Khi xong, **mở một PR vào `main` chỉ chứa Bước 0** (tôi cho phép mở PR này), rồi **dừng và báo tôi để merge**. Plan không cho trộn sửa đúng/sai với làm mượt trong một PR.
   - Khi tôi báo đã merge, đưa nhánh của bạn về `main` mới nhất rồi làm tiếp.
2. **Bước 1:** phần code của Task 0.2.
   - Ghi "baseline commit" vào `docs/perf/2026-11-baseline.md`, kèm quy trình đo cho tôi.
3. **Phase 4, rồi Phase 5**, theo bảng thứ tự ở README § 4, sau khi đã áp các ruling P1–P9.
4. **Review toàn nhánh** ở mức `max`.
   - Một đợt sửa, một lần review lại có giới hạn phạm vi, rồi phán xử phần còn lại.
   - Viết báo cáo `docs/superpowers/reports/<ngày>-phases-4-5-report.md`, theo dạng của báo cáo Phase 0–3:
     - tóm tắt tiếng Việt;
     - những gì đã kiểm;
     - danh sách **"chưa đo"**;
     - phần còn lại theo task;
     - mọi ruling, mỗi ruling kèm giá phải trả nếu sai.
5. **Mở PR Phase 4–5 vào `main`** (tôi cho phép).
   - Có mục "Cần duyệt thiết kế" cho 5.1 và 5.2, và mục "Việc của người dùng" trỏ tới các tài liệu đo.
   - **Không merge**; tôi merge sau khi duyệt.

## Những điều bắt buộc

- Bạn không có máy, simulator hay Instruments.
  - Mọi bước "Đo", "chụp màn", "duyệt thiết kế", "spike trên máy" chép vào `docs/perf/2026-11-device-perf-phase4-5.md` (theo task, có ô để điền), và không bao giờ báo là đã làm.
  - Task xong về code khi qua review và CI.
- Phần app chỉ được biên dịch bởi CI "App builds".
  - Sau mỗi lần push, đọc dòng `… warnings in the build, … in ios/JP27, ios/JP27Widgets, ios/Shared`. Phải là 0 và 0.
  - CI đỏ hay có warning là finding Critical của task vừa xong.
  - Chờ CI bằng lời nhắc hẹn giờ, không poll.
- Không chạm `src/data` (quy tắc R-86, đầu `src/data/id-renames.ts`).
  - Quy tắc chạy thử, lỗi lưu không im lặng và các lint khác giữ nguyên (README § 6).
- Không ghi tên hay mã model vào bất kỳ file, comment hay commit message nào của repo, ngoài dòng attribution mà phiên quy định.
- Chỉ push lên nhánh phiên của bạn chỉ định.
  - Ngoài hai PR ở trên, không tạo PR nào khác.
  - Không merge gì cả.
- Ngoài điểm dừng của Bước 0, chỉ dừng hỏi tôi khi gặp một trong các trường hợp:
  - thao tác không đảo ngược được;
  - việc nhạy cảm về bảo mật;
  - tác dụng phụ ngoài nhánh mà thông lệ phải hỏi;
  - plan hỏng tới mức mọi hướng đều là đoán.

  Ngoài các trường hợp đó, ra ruling theo dạng `Ruling: <quyết định> — <vì sao> — <giá nếu sai>`, ghi ledger, rồi đi tiếp.
- Giữa các task, không cần báo cáo tiến độ cho tôi. Khi xong (hoặc tới điểm dừng), gửi tôi:
  - những gì đã làm;
  - link PR;
  - danh sách **"Ruling tôi đã ra"**, mỗi ruling kèm giá nếu sai;
  - việc tôi cần làm trên máy.
