# GridRunner - Godot 4 Version

Game 3D điều khiển phi thuyền bằng 2 tay sử dụng Computer Vision.

## Yêu cầu

### Python (Hand Tracking Server)
```bash
pip install -r ..\requirements.txt
# hoặc:
pip install opencv-python mediapipe
```

### Godot
- Godot 4.2 trở lên
- Download: https://godotengine.org/download

## Cách chạy

### Cách 1: Tự động (Khuyến nghị)
1. Mở Godot Engine
2. Import project từ folder `d:\HT\GridRunner\godot\`
3. Nhấn **F5** - Hand Tracker (v2 Optimized) sẽ **tự động khởi động**!
4. Ở menu chính, nhấn **BẮT ĐẦU** → màn hình customizer sẽ mở ra để chọn Body/Wings/Tail/Engine trước khi vào đua
5. Giơ 2 tay lên trước camera

### Cách 2: Thủ công
```bash
# Terminal 1: Chạy Hand Tracker v2 (Optimized - Recommended)
cd d:\HT\GridRunner\godot
python hand_tracker_server.py --headless --fps 60 --target-fps 60 --scale 0.6 --model-complexity 0

# Sau đó mở Godot và nhấn F5
```

> Nếu thấy lỗi `ModuleNotFoundError: No module named 'cv2'`, hãy cài lại dependency bằng `pip install -r requirements.txt`.

### Tùy chỉnh Tracker
```bash
# Lower inference resolution for better FPS on slower systems
python hand_tracker_server.py --headless --scale 0.5

# Use different camera
python hand_tracker_server.py --headless --camera 1

# Adjust detection confidence
python hand_tracker_server.py --headless --confidence 0.4

# Fixed 60FPS request + low-latency preset
python hand_tracker_server.py --headless --fps 60 --target-fps 60 --scale 0.6 --model-complexity 0
```

## Điều khiển

### Cử chỉ tay
| Cử chỉ | Hành động |
|--------|-----------|
| Xoay "vô lăng" 2 tay | Lái trái/phải (steering + roll) |
| Đẩy vô lăng ra trước | Tăng ga (throttle) |
| Kéo vô lăng về gần camera | Phanh (brake) |
| Lắc nhanh vô lăng hoặc đẩy mạnh | Trigger boost |
| Nâng vô lăng lên nhanh | Dùng item đang giữ |

### Keyboard + Mouse
| Điều khiển | Hành động |
|------------|-----------|
| **WASD / Arrow Keys** | Lái phi thuyền |
| **Mouse (giữ chuột trái)** | Điều khiển hướng bay theo con trỏ |
| **Shift / Ctrl** | Boost / Brake |
| **Tab hoặc F9** | Chuyển mode: Hand / KB+Mouse / Hybrid |

### Phím tắt
| Phím | Hành động |
|------|-----------|
| **R** | Chơi lại |
| **F3** | Bật/tắt Debug Mode |
| **F4** | Calibrate điều khiển |
| **1** | Preset: Default |
| **2** | Preset: Sensitive |
| **3** | Preset: Smooth |
| **4** | Preset: Beginner |
| **F5/F6/F7/F8** | Đổi Body/Wing/Tail/Engine của phi thuyền |
| **5/6/7/8** | Đổi màu Body/Wing/Tail/Engine |
| **Shift + F5..F8 hoặc Shift + 5..8** | Lùi variant/màu trước đó |
| **ESC** | Thoát |

## Hệ thống Control Mapping

### Presets điều khiển
- **Default**: Cân bằng giữa độ nhạy và độ mượt
- **Sensitive**: Phản hồi nhanh, độ nhạy cao
- **Smooth**: Chuyển động mượt mà, ít rung
- **Beginner**: Dễ điều khiển cho người mới

### Calibration (F4)
1. Nhấn F4 khi game đang chạy
2. Chọn kiểu cầm ở menu: **Cầm ngang** hoặc **Cầm dọc**
3. Giữ vô lăng ở vị trí neutral (thẳng, ổn định)
4. Đợi thanh progress hoàn tất (~2 giây)
5. Cấu hình sẽ tự động lưu

## Tính năng

### ✅ Đã hoàn thành

#### Gameplay
- **5 loại obstacle**: Box, Sphere, Cylinder, Ring, Cross
- **Combo system**: Bonus điểm khi dodge liên tục
- **Near-miss bonus**: +5 điểm khi né sát obstacle
- **Warning system**: Màn hình đỏ + camera shake khi gần va chạm
- **Collision rework**: va vào obstacle không còn game-over tức thì, thay vào đó bị giảm tốc theo mức boost hiện tại
- **Support items**: buff cho bản thân (Boost/Shield) + debuff đối thủ (Rival Slow/Jammer)
- **Pause menu**: ESC để pause/resume
- **Pause overlay nâng cấp**: khi pause sẽ dim nền, gom thông tin trọng tâm và ẩn bớt HUD gây rối
- **Background stars**: Twinkle effect cho depth
- **Steering nâng cấp**: phản hồi lái ổn định hơn theo `delta`, roll mượt hơn theo lateral movement
- **Pre-game ship customizer flow mới**: customizer xuất hiện sau khi bấm Start (không mở sẵn ở menu)
- **Ship customization runtime**: vẫn có thể đổi nhanh bằng F5/F6/F7/F8 trong game
- **Campaign race nhiều stage**: cốt truyện từ mở đầu đến kết thúc, tiến cấp stage khi thắng
- **Rival AI nâng cấp**: đối thủ đổi lane, tăng/giảm tốc, block/overtake đa dạng hơn

#### Hand Tracking
- **Hand Control Mapper**: Bộ ánh xạ điều khiển hoàn chỉnh
  - Dead zones, sensitivity, smoothing
  - Calibration tự động (F4)
  - 4 presets sẵn có (phím 1-4)
  - Lưu/load cấu hình
- **Improved tracking**: Track grip point (thumb/index) theo từng tay
- **Left/Right detection**: Tự động xác định tay trái/phải
- **Tilt indicator**: Thanh hiển thị độ nghiêng
- **Smoothing**: One Euro + Kalman hybrid

#### Visual
- **Auto-launch**: Tracker tự khởi động cùng game
- Particles effects (engine, trail, boost, explosion)
- Neon glow materials
- **Ship parts procedural**: thân/cánh/đuôi/động cơ được tạo từ capsule, prism, torus, cylinder (không còn chỉ khối hộp đơn giản)
- **Per-part colors**: đổi màu độc lập cho từng bộ phận phi thuyền
- **Track upgrade**: nâng đường đua thành digital technical-grid network (lưới số ổn định hơn)
- **Track flow nâng cấp**: nhịp cua/chuyển hướng đa dạng hơn, giảm cảm giác chạy một đường thẳng kéo dài
- **Background upgrade**: thêm nebula clouds và hành tinh xa
- **Chase camera nâng cấp**: camera look-ahead + dynamic FOV theo tốc độ, cảm giác lái "phi thuyền" rõ hơn
- Camera shake khi game over
- **Debug Mode (F3)** - hiển thị collision boxes

#### Audio
- **Soundtrack ưu tiên file ngoài**: game tự phát `res://audio/Smart_Systems.mp3` nếu có, và fallback về procedural soundtrack nếu thiếu file.
- **Audio settings** trong menu: chỉnh Master / Music / SFX theo thang **1-100%**.

#### Pixelpart integration
- Hệ thống đã có hook ưu tiên Pixelpart effect tại `res://effects/hit_impact.res` nếu bạn import sẵn effect resource.
- Nếu chưa có file effect Pixelpart, game tự fallback sang GPUParticles3D.

#### System
- High score lưu trữ
- Difficulty tăng dần theo thời gian
- Obstacle pooling để giảm giật khi spawn liên tục
- Runtime profiler (debug build) để theo dõi FPS spike
- State stack bằng YAFSM cho flow `playing/paused/calibration/game_over`

### 🎮 Gameplay
- Tránh chướng ngại vật để ghi điểm
- Độ khó tăng dần (obstacles spawn nhanh hơn)
- Boost bằng cử chỉ lắc/đẩy vô lăng, và dùng item bằng cử chỉ nâng vô lăng

### 🔧 Debug Mode (F3)
Khi bật debug mode:
- Hiển thị collision boxes (cyan = spaceship, red = obstacles)
- Hiển thị hand tracking data
- Hiển thị spawn interval và số obstacles

## Hand Tracking

### Phiên bản Tracker
- **v2 (Mới - Khuyến nghị)**: CPU-optimized pipeline, adaptive inference scale, One Euro + Kalman smoothing

### Điểm được track
- **Chấm vàng**: Grip point mỗi tay (trung bình thumb_tip + index_tip)
- **Đường vàng**: Nối giữa 2 grip point  
- **Chấm hồng**: Trung điểm (điều khiển phi thuyền)
- **Mũi tên trắng**: Hướng nghiêng

### Thông số gửi đến Godot
- `mid_x, mid_y`: Vị trí trung điểm (0-1)
- `angle`: Góc nghiêng giữa 2 tay (radian)
- `distance`: Độ sâu vô lăng đã chuẩn hóa (0-1)

## Kiến trúc

```
Godot (main.gd)
    │
    │ OS.create_process()
    ▼
Python (hand_tracker_server.py) [CPU-optimized]
    │
    │ Capture thread (latest frame only)
    │ Inference + adaptive scale
    │ One Euro + Kalman smoothing
    │ UDP send
    │
    │ UDP Port 5555
    │ JSON: {found, mid_x, mid_y, angle, distance, hands}
    ▼
Godot (receive_hand_data)
    │
    ├── spaceship.gd  (điều khiển phi thuyền + particles)
    ├── obstacle.gd   (chướng ngại vật + pulsing glow)
    └── UI            (score, high score, status, instructions)
```

## Cấu trúc thư mục

```
godot/
├── project.godot             # Godot project file
├── hand_tracker_server.py    # Python hand tracking v2 (CPU optimized, auto-launched)
├── icon.svg
├── README.md
├── addons/
│   └── debug_draw_3d/        # Debug visualization addon
├── scenes/
│   ├── main.tscn             # Main scene
│   ├── spaceship.tscn        # Phi thuyền
│   └── obstacle.tscn         # Chướng ngại vật
└── scripts/
    ├── main.gd               # Game controller + auto-launch tracker v2
    ├── spaceship.gd          # Spaceship logic + particles
    └── obstacle.gd           # Obstacle logic
```
