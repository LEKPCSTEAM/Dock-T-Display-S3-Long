# LongDeck — นาฬิกา NTP สำหรับ T-Display-S3-Long

นาฬิกาตั้งโต๊ะจอ 640x180 sync เวลาจาก NTP (โซนเวลาไทย `ICT-7`) ตั้งค่า WiFi ผ่านมือถือได้ และมีเว็บตั้งค่าในวง LAN

## Build / Flash

```bash
pio run -e ntp_clock -t upload
pio device monitor -b 115200
```

`platformio.ini` ตั้ง `default_envs = ntp_clock` ไว้แล้ว (`src_dir` ของ repo นี้อิงตาม `default_envs`)

Flash ครั้งแรกหลังเพิ่ม LongDeck ต้องเขียน partition table ใหม่ (`partitions_longdeck.csv`) — คำสั่ง upload ข้างบนทำให้เอง และจะ format partition เก็บข้อมูล deck ใหม่ ส่วน WiFi/settings ที่บันทึกไว้ไม่หาย (NVS offset เดิม, settings migrate เอง)

## ตั้งค่า WiFi ครั้งแรก

1. เปิดเครื่องครั้งแรก (หรือต่อ WiFi เดิมไม่ได้ใน 20 วินาที) จอจะขึ้นหน้า **ตั้งค่า WiFi** พร้อม QR
2. สแกน QR ซ้าย หรือต่อ WiFi ชื่อ `LongDeck-XXXX` (ไม่มีรหัส)
3. หน้า captive portal เปิดเอง (หรือเข้า `http://192.168.4.1`) เลือก WiFi บ้าน ใส่รหัส แล้วกดบันทึก
4. ต่อสำเร็จจะบันทึกลง NVS แล้วกลับหน้านาฬิกาเอง — ถ้ารหัสผิด ค่าเดิมยังอยู่

เปลี่ยน WiFi ภายหลัง: กดปุ่ม BOOT ค้าง 2 วินาที, หรือกดปุ่ม "ตั้งค่า WiFi" ในหน้า System, หรือจากเว็บตั้งค่า

## การใช้งาน

| ทำอะไร | ผล |
| --- | --- |
| ปัดซ้าย/ขวา หรือกดปุ่ม BOOT | เปลี่ยนหน้า: นาฬิกา → ปฏิทิน/นาฬิกาเข็ม → Focus timer → System |
| แตะตัวเลขเวลาในหน้าแรก | สลับธีม สีประจำวัน / สีรุ้ง / ขาวเรียบ |
| หน้า Focus: แตะ / กดค้าง | เริ่ม-หยุด Pomodoro / รีเซ็ต |
| เปิด `http://longdeck.local` | เว็บตั้งค่า: ความสว่าง, หรี่จอกลางคืน, ธีม, เมืองสำหรับพยากรณ์อากาศ, sync เวลา, เปลี่ยน WiFi |

## LongDeck (Stream Deck)

แอป menu-bar บน Mac จับคู่กับบอร์ดผ่าน WiFi แล้วแสดงปุ่มแบบ Stream Deck บนจอ

1. Build แอป: `cd mac/LongDeck && ./scripts/bundle.sh` แล้วเปิด `mac/LongDeck/build/LongDeck.app`
2. Config อยู่ที่ `~/Library/Application Support/LongDeck/config.json` (สร้างหน้า Dev ตัวอย่างให้ตอนรันครั้งแรก) เปิดเมนู "Edit layout…" ลาก widget วางบน grid 8x2 แล้วกด Save เพื่อ push ขึ้นบอร์ด (แก้ไฟล์ด้วยมือก็ยังได้ แอปอ่านใหม่เอง) — ถ้า config ผิดจะแสดง error และไม่ push; layout frame ต้องไม่เกิน 15360 bytes ถ้าเกิน editor จะปิดปุ่ม Save (disabled) และแสดง error ใน issue list จนกว่าจะแก้
3. จับคู่: เมนู "Pair with board…" เลือกบอร์ด แล้วพิมพ์รหัส 6 หลักที่แสดงบนจอบอร์ด (ใช้ได้ 60 วินาที)
4. ปุ่ม hotkey / media / volume / type-text ต้องอนุญาต Accessibility — เมนู "Grant Accessibility…"
5. หน้า deck ต่อท้าย นาฬิกา → ปฏิทิน → Focus → System ได้สูงสุด 8 หน้า (grid 8x2) ถ้าแอปไม่ได้เชื่อมต่อจะขึ้นป้าย "Mac offline" และปุ่มจางลง

### Live widgets

หน้า deck ใส่ live widget ได้ 3 แบบ: `stat` (CPU / RAM / GPU / temp / net / disk / battery แบบ bar, number หรือ sparkline), `volume` (slider + ปุ่ม mute) และ `clock` ค่า stat ส่งมาจากแอป Mac ทุกวินาที ถ้า Mac offline ทุก stat และ volume จะแสดง `--` ส่วน clock เดินต่อด้วยเวลาของบอร์ดเอง (`--:--` ถ้ายังไม่ sync NTP) ลาก slider เพื่อปรับ volume ของ Mac (ลากบน slider จะไม่เปลี่ยนหน้า) แตะไอคอนลำโพงเพื่อ mute / unmute ใน cell 1x1 หน่วย rate จะย่อเหลือตัวอักษรเดียว (เช่น `123M`) และ volume ที่ใช้ไม่ได้แสดง `n/a` รูปแบบ config ดู `mac/LongDeck/README.md`

### Claude Code

ต้อง Install integration จากเมนูแอป Mac ก่อน (ดู `mac/LongDeck/README.md`) แอปจะเพิ่ม command hook 9 event (รวม `PostToolUseFailure`) ลง `~/.claude/settings.json` ซึ่งเรียก `~/Library/Application Support/LongDeck/hook.sh` script นี้ส่ง event ให้แอป (รอไม่เกิน 0.5 วินาที) ไม่พิมพ์อะไรออกมา และ exit 0 เสมอ ถ้าแอปไม่ได้เปิด Claude Code ก็ทำงานปกติและไม่มี hook error

หลัง Uninstall ให้ restart session ของ Claude Code ที่เปิดค้างไว้ ไม่งั้น session เดิมจะยังเรียก `hook.sh` ที่ถูกลบไปแล้วและขึ้น hook error (หลัง Install ก็ต้อง restart เพื่อให้ session โหลด hook)

หน้า `Claude` มี 2 widget

- `claude_sessions` — แถวละ session: จุดสี accent = working, เหลือง = รอ permission, เขียว = waiting (เสร็จแล้วรอ prompt), เทา = อื่น ๆ ถ้าเกินจำนวนแถวจะขึ้น `+N more`
- `claude_usage` — 5h / 7d เป็น % พร้อม countdown reset: bar สี accent ปกติ, เหลืองเมื่อ ≥ 80%, แดงเมื่อ ≥ 95%
- Mac offline, ยังไม่ Install หรือ listener ของแอปยังไม่ทำงาน: ทั้งสอง widget แสดง `--` (หลัง Uninstall หรือ listener ล่ม จะขึ้น `No sessions` จนกว่าบอร์ดจะ reconnect)

แตะแถว session = focus หน้าต่าง iTerm2/tmux ของ session นั้น, กดค้างแถวที่กำลัง working = interrupt (Escape ส่งเฉพาะตอนจอ Claude Code ขึ้น `esc to interrupt`)

เมื่อ Claude ขอ permission จะมี overlay ขึ้นทับ**ทุกหน้า** (รวมหน้านาฬิกา) พร้อมจอกะพริบ มีปุ่ม Approve / Always / Deny / Open และ ✕ (ซ่อนจนกว่าจะมี prompt ใหม่; overlay ไม่รับ tap 600 ms แรก) Deny = "No" แล้ว Claude หยุดรอ

แอป Mac จะตอบแทนบอร์ดเฉพาะเมื่อ verify dialog ใน tmux ได้ตรงทุกจุด ถ้าไม่ได้บอร์ดจะขึ้น toast "Answer at the keyboard" และไม่พิมพ์อะไรลง pane

- รองรับเฉพาะ prompt ของ Bash / Edit / MultiEdit / Write / Read
- Always มีเฉพาะ Bash ที่เป็นบรรทัดเดียว ไม่เกิน 55 bytes ไม่มี shell operator และ rule ที่ Claude Code จะบันทึกต้องเท่ากับคำสั่งทั้งบรรทัด — Edit/Write/Read ไม่ส่ง Always จากบอร์ด
- คำสั่งยาวที่ wrap หลายบรรทัดมักถูกปฏิเสธ ให้ตอบที่คีย์บอร์ด
- overlay ยังค้างอยู่ตราบที่ pane มี dialog ของ tool เดียวกัน (เช็กทุก 1 วินาที) แม้ verify ไม่ผ่านจนตอบจากบอร์ดไม่ได้

ยกเลิกการจับคู่ Mac: กดปุ่ม forget ในเว็บตั้งค่า หรือ

```bash
curl -X POST http://longdeck.local/api/deck/forget
```

(เป็น POST เท่านั้น; ใช้ไม่ได้ตอนอยู่ในโหมด portal และ browser ข้าม origin จะถูกปฏิเสธ 403)

ข้อจำกัด: อุปกรณ์ไหนใน LAN ก็เริ่มจับคู่ใหม่ได้ (บอร์ดจะแสดงรหัสบนจอ) และการจับคู่ใหม่จะแทนที่ key เดิม

## ลูกเล่น

- ตัวเลขเลื่อนแบบ rolling ทุกครั้งที่เปลี่ยน, แถบวินาทีวิ่งต่อเนื่องเต็มความกว้างจอ, ฉลองต้นชั่วโมง
- สี accent ตามสีประจำวันแบบไทย, วันที่ภาษาไทยแบบ พ.ศ.
- สภาพอากาศปัจจุบันจาก Open-Meteo (ไม่ต้องใช้ API key) อัปเดตทุก 15 นาที
- หน้าปฏิทิน: นาฬิกาเข็ม, วันที่ของปี/สัปดาห์, % ของปีที่ผ่านไป, นับถอยหลังวันสำคัญถัดไป
- 22:00–06:00 หรี่จอและเปลี่ยนเป็นโทนแดงอัตโนมัติ (ปิดได้)

## แก้หน้าตาด้วย EEZ Studio

Layout และ style ของทุกหน้าอยู่ใน `eez/longdeck.eez-project` (LVGL 8.4.0, 640x180, ไม่ใช้ Flow) ส่วน logic ทั้งหมดอยู่ใน C++

1. เปิด `eez/longdeck.eez-project` ใน EEZ Studio แล้วแก้ตำแหน่ง/สี/font ได้เลย
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
