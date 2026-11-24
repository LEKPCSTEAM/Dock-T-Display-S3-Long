# ThaiClock — นาฬิกา NTP สำหรับ T-Display-S3-Long

นาฬิกาตั้งโต๊ะจอ 640x180 sync เวลาจาก NTP (โซนเวลาไทย `ICT-7`) ตั้งค่า WiFi ผ่านมือถือได้ และมีเว็บตั้งค่าในวง LAN

## Build / Flash

```bash
pio run -e ntp_clock -t upload
pio device monitor -b 115200
```

`platformio.ini` ตั้ง `default_envs = ntp_clock` ไว้แล้ว (`src_dir` ของ repo นี้อิงตาม `default_envs`)

## ตั้งค่า WiFi ครั้งแรก

1. เปิดเครื่องครั้งแรก (หรือต่อ WiFi เดิมไม่ได้ใน 20 วินาที) จอจะขึ้นหน้า **ตั้งค่า WiFi** พร้อม QR
2. สแกน QR ซ้าย หรือต่อ WiFi ชื่อ `ThaiClock-XXXX` (ไม่มีรหัส)
3. หน้า captive portal เปิดเอง (หรือเข้า `http://192.168.4.1`) เลือก WiFi บ้าน ใส่รหัส แล้วกดบันทึก
4. ต่อสำเร็จจะบันทึกลง NVS แล้วกลับหน้านาฬิกาเอง — ถ้ารหัสผิด ค่าเดิมยังอยู่

เปลี่ยน WiFi ภายหลัง: กดปุ่ม BOOT ค้าง 2 วินาที, หรือกดปุ่ม "ตั้งค่า WiFi" ในหน้า System, หรือจากเว็บตั้งค่า

## การใช้งาน

| ทำอะไร | ผล |
| --- | --- |
| ปัดซ้าย/ขวา หรือกดปุ่ม BOOT | เปลี่ยนหน้า: นาฬิกา → ปฏิทิน/นาฬิกาเข็ม → Focus timer → System |
| แตะตัวเลขเวลาในหน้าแรก | สลับธีม สีประจำวัน / สีรุ้ง / ขาวเรียบ |
| หน้า Focus: แตะ / กดค้าง | เริ่ม-หยุด Pomodoro / รีเซ็ต |
| เปิด `http://thaiclock.local` | เว็บตั้งค่า: ความสว่าง, หรี่จอกลางคืน, ธีม, เมืองสำหรับพยากรณ์อากาศ, sync เวลา, เปลี่ยน WiFi |

## ลูกเล่น

- ตัวเลขเลื่อนแบบ rolling ทุกครั้งที่เปลี่ยน, แถบวินาทีวิ่งต่อเนื่องเต็มความกว้างจอ, ฉลองต้นชั่วโมง
- สี accent ตามสีประจำวันแบบไทย, วันที่ภาษาไทยแบบ พ.ศ.
- สภาพอากาศปัจจุบันจาก Open-Meteo (ไม่ต้องใช้ API key) อัปเดตทุก 15 นาที
- หน้าปฏิทิน: นาฬิกาเข็ม, วันที่ของปี/สัปดาห์, % ของปีที่ผ่านไป, นับถอยหลังวันสำคัญถัดไป
- 22:00–06:00 หรี่จอและเปลี่ยนเป็นโทนแดงอัตโนมัติ (ปิดได้)

## แก้หน้าตาด้วย EEZ Studio

Layout และ style ของทุกหน้าอยู่ใน `eez/thaiclock.eez-project` (LVGL 8.4.0, 640x180, ไม่ใช้ Flow) ส่วน logic ทั้งหมดอยู่ใน C++

1. เปิด `eez/thaiclock.eez-project` ใน EEZ Studio แล้วแก้ตำแหน่ง/สี/font ได้เลย
2. กด **Build** — โค้ดจะถูกสร้างใน `eez/gen/` (ห้ามแก้ไฟล์ใน `gen/` ด้วยมือ)
3. `pio run -e ntp_clock -t upload`

ข้อควรรู้:

- ตอน boot `ui.cpp` เรียก `create_screen_<x>_page()` ทีละหน้าแล้วย้าย widget เข้า tile ของ tileview — **ไม่ได้ใช้** `create_screens()` / `gen/ui.c` (ตั้ง theme สว่าง) และไม่ link `gen/ui_font_*.c`
- font ตอนรันจริงมาจาก `fonts/` + `thai_fonts.c` (ซ้อนวรรณยุกต์บนสระบนได้) เลยสูงกว่า font ใน preview — ข้อความไทยบนจอจริงจะต่ำกว่าใน EEZ ราว 5–7 px
- โค้ดอ้าง widget ตามชื่อ (`objects.label_clock_sec` ฯลฯ) — เปลี่ยนชื่อ widget ใน EEZ แล้วต้องแก้ C++ ตาม
- ส่วนที่ยังสร้างในโค้ด: เข็มนาฬิกา (`lv_meter`), toast, flash, จุดบอกหน้า

## Hardware notes

- Touch ตรวจรุ่นเองตอน boot: เจอ I2C `0x3B` = touch ในตัว AXS15231B (บอร์ดรุ่นแรก), ไม่เจอ = CST3530 (ใช้ `hyn_driver`)
- ตั้ง PMU SY6970 ให้ input current limit 1500 mA และ SYS_MIN 3.7 V — ค่า default (500 mA / 3.5 V) ทำให้บอร์ดที่**ไม่ได้ต่อแบต** brownout / INT_WDT reset ตอน WiFi ส่งสัญญาณ และทำให้ touch มี ghost press
- อ่าน touch แบบ debounce (ต้องได้ค่าดี 3 ครั้งติดกันถึงนับว่ากด) กันค่าขยะจาก controller

## NTP

`time.navy.mi.th` (กรมอุทกศาสตร์), `clock.nectec.or.th`, `th.pool.ntp.org` — sync ซ้ำทุก 1 ชั่วโมง

## Font

`fonts/*.c` สร้างจาก [Kanit](https://github.com/cadsondemak/kanit) (SIL OFL 1.1) + FontAwesome ของ LVGL ด้วย `fonts/gen_fonts.sh`
