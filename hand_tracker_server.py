"""
GridRunner Hand Tracker Server v2 (CPU-optimized)
Theo dõi 2 tay qua webcam dùng MediaPipe, gửi dữ liệu qua UDP sang Godot.

Tối ưu CPU cho độ trễ thấp/FPS cao:
- model_complexity=0 (lite model)
- Inference scale thấp hơn frame camera (mặc định 0.6)
- Capture thread luôn giữ frame mới nhất (drop frame cũ)
- Adaptive scale để giữ target FPS
- Camera buffer size = 1 để giảm latency
"""

import argparse
import json
import math
import os
import socket
import sys
import threading
import time

try:
    import cv2
except ModuleNotFoundError:
    cv2 = None

try:
    # Import MediaPipe
    from mediapipe.python.solutions import drawing_utils, hands
except ModuleNotFoundError:
    drawing_utils = None
    hands = None


class Kalman1D:
    """Simple constant-velocity Kalman filter for smooth 1D tracking."""

    def __init__(self, process_var=1e-5, measurement_var=4e-4):
        self.x = 0.0
        self.v = 0.0
        self.P00 = 1.0
        self.P01 = 0.0
        self.P10 = 0.0
        self.P11 = 1.0
        self.q = float(process_var)
        self.r = float(measurement_var)
        self.initialized = False

    def reset(self, x, v=0.0):
        self.x = float(x)
        self.v = float(v)
        self.P00 = 1.0
        self.P01 = 0.0
        self.P10 = 0.0
        self.P11 = 1.0
        self.initialized = True

    def update(self, z, dt):
        """Update with measurement z and timestep dt."""
        z = float(z)
        dt = float(max(1e-4, dt))

        if not self.initialized:
            self.reset(z, 0.0)
            return self.x

        # Predict step
        x_pred = self.x + self.v * dt
        v_pred = self.v

        # Covariance update: P = A P A^T + Q
        P00 = self.P00 + dt * (self.P10 + self.P01) + (dt * dt) * self.P11
        P01 = self.P01 + dt * self.P11
        P10 = self.P10 + dt * self.P11
        P11 = self.P11

        # Add process noise
        P00 += self.q * dt * dt
        P11 += self.q

        # Update step (H = [1, 0])
        y = z - x_pred
        S = P00 + self.r
        K0 = P00 / S
        K1 = P10 / S

        self.x = x_pred + K0 * y
        self.v = v_pred + K1 * y

        self.P00 = (1.0 - K0) * P00
        self.P01 = (1.0 - K0) * P01
        self.P10 = P10 - K1 * P00
        self.P11 = P11 - K1 * P01

        return self.x


class OneEuro1D:
    """One Euro filter for low-latency smoothing."""

    def __init__(self, min_cutoff=1.2, beta=0.2, d_cutoff=1.0):
        self.min_cutoff = float(max(1e-4, min_cutoff))
        self.beta = float(max(0.0, beta))
        self.d_cutoff = float(max(1e-4, d_cutoff))
        self._x_prev = None
        self._dx_prev = 0.0

    @staticmethod
    def _alpha(cutoff, dt):
        cutoff = float(max(1e-4, cutoff))
        dt = float(max(1e-4, dt))
        tau = 1.0 / (2.0 * math.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)

    def reset(self, x):
        self._x_prev = float(x)
        self._dx_prev = 0.0

    def update(self, x, dt):
        x = float(x)
        dt = float(max(1e-4, dt))

        if self._x_prev is None:
            self.reset(x)
            return x

        dx = (x - self._x_prev) / dt
        alpha_d = self._alpha(self.d_cutoff, dt)
        dx_hat = self._dx_prev + alpha_d * (dx - self._dx_prev)

        cutoff = self.min_cutoff + self.beta * abs(dx_hat)
        alpha = self._alpha(cutoff, dt)
        x_hat = self._x_prev + alpha * (x - self._x_prev)

        self._x_prev = x_hat
        self._dx_prev = dx_hat
        return x_hat


def wrap_angle_rad(a):
    """Wrap angle to [-pi, pi]."""
    return (a + math.pi) % (2.0 * math.pi) - math.pi


def unwrap_angle_rad(prev_unwrapped, a_wrapped):
    """Unwrap to be closest to previous unwrapped value."""
    if prev_unwrapped is None:
        return a_wrapped
    delta = a_wrapped - wrap_angle_rad(prev_unwrapped)
    if delta > math.pi:
        a_wrapped -= 2.0 * math.pi
    elif delta < -math.pi:
        a_wrapped += 2.0 * math.pi
    return prev_unwrapped + (a_wrapped - wrap_angle_rad(prev_unwrapped))


TRACKING_PACKET_KEYS = ("found", "mid_x", "mid_y", "angle", "distance", "hands")


def _coerce_packet_float(name, value, min_value, max_value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError(f"'{name}' must be numeric.")
    return max(min_value, min(max_value, float(value)))


def normalize_tracking_packet(raw_data):
    if not isinstance(raw_data, dict):
        raise TypeError("Tracking payload must be a dictionary.")

    missing = [key for key in TRACKING_PACKET_KEYS if key not in raw_data]
    if missing:
        raise ValueError(f"Tracking payload missing keys: {', '.join(missing)}")

    found_value = raw_data["found"]
    if not isinstance(found_value, bool):
        raise TypeError("'found' must be bool.")

    hands_value = raw_data["hands"]
    if isinstance(hands_value, bool) or not isinstance(hands_value, (int, float)):
        raise TypeError("'hands' must be numeric.")

    normalized = {
        "found": bool(found_value),
        "mid_x": _coerce_packet_float("mid_x", raw_data["mid_x"], 0.0, 1.0),
        "mid_y": _coerce_packet_float("mid_y", raw_data["mid_y"], 0.0, 1.0),
        "angle": _coerce_packet_float("angle", raw_data["angle"], -math.pi, math.pi),
        "distance": _coerce_packet_float("distance", raw_data["distance"], 0.0, 1.0),
        "hands": max(0, min(2, int(hands_value))),
    }

    if normalized["hands"] < 2:
        normalized["found"] = False

    return normalized


class HandTrackerServer:
    def __init__(
        self,
        udp_port=5555,
        camera_index=0,
        headless=False,
        frame_width=640,
        frame_height=480,
        camera_fps=60,
        inference_scale=0.6,
        model_complexity=0,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.4,
        target_fps=60,
        adaptive_scale=True,
        stop_file=None,
    ):
        print("Initializing Hand Tracker Server v2 (CPU-optimized)...")
        missing_deps = []
        if cv2 is None:
            missing_deps.append("opencv-python (cv2)")
        if hands is None or drawing_utils is None:
            missing_deps.append("mediapipe")
        if missing_deps:
            print("\nERROR: Missing Python dependencies: %s" % ", ".join(missing_deps))
            print("Install dependencies from repository root:")
            print("  pip install -r requirements.txt")
            print("Or install directly:")
            print("  pip install opencv-python mediapipe")
            sys.exit(1)

        self.headless = headless
        self.udp_port = udp_port
        self.frame_width = int(max(320, frame_width))
        self.frame_height = int(max(240, frame_height))
        self.camera_fps = int(max(15, camera_fps))
        self.inference_scale = float(max(0.35, min(1.0, inference_scale)))
        self.min_inference_scale = 0.35
        self.max_inference_scale = 1.0
        self.adaptive_scale = bool(adaptive_scale)
        self.target_fps = int(max(15, target_fps))
        self.model_complexity = int(max(0, min(1, model_complexity)))
        self.min_detection_confidence = float(max(0.1, min(0.95, min_detection_confidence)))
        self.min_tracking_confidence = float(max(0.1, min(0.95, min_tracking_confidence)))
        self.stop_file = stop_file if stop_file else None
        if self.stop_file and os.path.exists(self.stop_file):
            try:
                os.remove(self.stop_file)
            except OSError as err:
                print(f"Warning: failed to remove stale stop flag '{self.stop_file}': {err}")

        # UDP Socket
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.godot_address = ("127.0.0.1", udp_port)

        # MediaPipe Hands (lite model for speed)
        self.hands = hands.Hands(
            static_image_mode=False,
            max_num_hands=2,
            model_complexity=self.model_complexity,
            min_detection_confidence=self.min_detection_confidence,
            min_tracking_confidence=self.min_tracking_confidence,
        )
        self.drawing_utils = drawing_utils

        # Camera
        self.cap = self.open_camera(camera_index)
        if self.cap is None:
            print("\nERROR: Could not open camera!")
            print("Solutions: Close Zoom/Teams/Browser, check camera settings")
            sys.exit(1)

        # One Euro filters for low-latency smoothing at grip-point level
        self.of_left_x = OneEuro1D(min_cutoff=1.2, beta=0.22, d_cutoff=1.0)
        self.of_left_y = OneEuro1D(min_cutoff=1.2, beta=0.22, d_cutoff=1.0)
        self.of_right_x = OneEuro1D(min_cutoff=1.2, beta=0.22, d_cutoff=1.0)
        self.of_right_y = OneEuro1D(min_cutoff=1.2, beta=0.22, d_cutoff=1.0)
        self.of_left_z = OneEuro1D(min_cutoff=1.0, beta=0.15, d_cutoff=1.0)
        self.of_right_z = OneEuro1D(min_cutoff=1.0, beta=0.15, d_cutoff=1.0)

        # Kalman filters tuned for lower latency on CPU pipeline
        self.kf_left_x = Kalman1D(process_var=3e-5, measurement_var=2e-4)
        self.kf_left_y = Kalman1D(process_var=3e-5, measurement_var=2e-4)
        self.kf_right_x = Kalman1D(process_var=3e-5, measurement_var=2e-4)
        self.kf_right_y = Kalman1D(process_var=3e-5, measurement_var=2e-4)
        self.kf_angle = Kalman1D(process_var=1e-4, measurement_var=1.2e-3)
        self.kf_depth = Kalman1D(process_var=6e-5, measurement_var=6e-4)
        self.depth_scale = 2.5

        # State tracking
        self._last_ts = time.time()
        self._had_two_hands_last = False
        self._last_angle_unwrapped = None

        # Stats
        self.running = True
        self.frame_count = 0
        self.fps = 0.0
        self.last_fps_time = time.time()
        self.fps_counter = 0

        # Capture thread state: always keep only newest frame
        self._frame_lock = threading.Lock()
        self._latest_frame = None
        self._capture_thread = threading.Thread(target=self._capture_frames_loop, daemon=True)
        self._capture_thread.start()

    def open_camera(self, preferred_index=0):
        """Try multiple camera backends and indices."""
        backends = [
            (cv2.CAP_DSHOW, "DirectShow"),
            (cv2.CAP_MSMF, "Media Foundation"),
            (cv2.CAP_ANY, "Auto"),
        ]

        indices = [preferred_index]
        if preferred_index not in [0, 1, 2]:
            indices.extend([0, 1, 2])
        else:
            indices.extend([i for i in [0, 1, 2] if i != preferred_index])

        for backend, backend_name in backends:
            for idx in indices:
                if not self.headless:
                    print(f"  Trying camera {idx} with {backend_name}...")
                try:
                    cap = cv2.VideoCapture(idx, backend)
                    time.sleep(0.3)

                    if cap.isOpened():
                        for _ in range(5):
                            ret, frame = cap.read()
                            if ret and frame is not None and frame.size > 0:
                                if not self.headless:
                                    print(f"  ✓ Camera {idx} opened!")
                                cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.frame_width)
                                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.frame_height)
                                cap.set(cv2.CAP_PROP_FPS, self.camera_fps)
                                cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
                                cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
                                return cap
                            time.sleep(0.1)
                        cap.release()
                except cv2.error as err:
                    if not self.headless:
                        print(f"  Camera backend error ({backend_name}, index={idx}): {err}")
                    continue
                except OSError as err:
                    if not self.headless:
                        print(f"  Camera I/O error ({backend_name}, index={idx}): {err}")
                    continue

        return None

    def _capture_frames_loop(self):
        while self.running:
            ret, frame = self.cap.read()
            if not ret or frame is None:
                time.sleep(0.002)
                continue
            with self._frame_lock:
                self._latest_frame = frame

    def _get_latest_frame(self):
        with self._frame_lock:
            frame = self._latest_frame
            self._latest_frame = None
        return frame

    def _stop_requested(self):
        return bool(self.stop_file) and os.path.exists(self.stop_file)

    def get_hand_center(self, hand_landmarks):
        """Get palm center as average of base knuckles (landmarks 5, 9, 13)."""
        key_points = [5, 9, 13]
        x_sum = sum(hand_landmarks.landmark[i].x for i in key_points)
        y_sum = sum(hand_landmarks.landmark[i].y for i in key_points)
        return x_sum / len(key_points), y_sum / len(key_points)

    def get_grip_point(self, hand_landmarks):
        """Get grip point from thumb tip (4) and index tip (8) + mean depth."""
        thumb_tip = hand_landmarks.landmark[4]
        index_tip = hand_landmarks.landmark[8]
        grip_x = (thumb_tip.x + index_tip.x) * 0.5
        grip_y = (thumb_tip.y + index_tip.y) * 0.5
        grip_z = (thumb_tip.z + index_tip.z) * 0.5
        return grip_x, grip_y, grip_z

    def _auto_tune_inference_scale(self):
        if not self.adaptive_scale:
            return

        old_scale = self.inference_scale
        if self.fps < self.target_fps * 0.9 and self.inference_scale > self.min_inference_scale:
            self.inference_scale = max(self.min_inference_scale, round(self.inference_scale - 0.05, 2))
        elif self.fps > self.target_fps * 1.15 and self.inference_scale < self.max_inference_scale:
            self.inference_scale = min(self.max_inference_scale, round(self.inference_scale + 0.05, 2))

        if self.inference_scale != old_scale:
            print(
                f"[Perf] FPS={self.fps:.1f}, target={self.target_fps}, "
                f"inference_scale {old_scale:.2f} -> {self.inference_scale:.2f}"
            )

    def calculate_fps(self):
        """Calculate FPS every second."""
        self.fps_counter += 1
        current_time = time.time()
        elapsed = current_time - self.last_fps_time
        if elapsed >= 1.0:
            self.fps = self.fps_counter / elapsed
            self.fps_counter = 0
            self.last_fps_time = current_time
            self._auto_tune_inference_scale()

    def process_frame(self, frame):
        """Process video frame and return frame + tracking data."""
        frame = cv2.flip(frame, 1)
        h, w, _ = frame.shape

        if self.inference_scale < 0.999:
            infer_w = max(160, int(w * self.inference_scale))
            infer_h = max(120, int(h * self.inference_scale))
            inference_frame = cv2.resize(frame, (infer_w, infer_h), interpolation=cv2.INTER_AREA)
        else:
            inference_frame = frame

        rgb_frame = cv2.cvtColor(inference_frame, cv2.COLOR_BGR2RGB)
        rgb_frame.flags.writeable = False
        results = self.hands.process(rgb_frame)
        rgb_frame.flags.writeable = True

        data = {
            "found": False,
            "mid_x": 0.5,
            "mid_y": 0.5,
            "angle": 0.0,
            "distance": 0.5,
            "hands": 0,
        }

        # Compute dt for filters
        now = time.time()
        dt = now - self._last_ts
        self._last_ts = now
        dt = max(1.0 / 180.0, min(1.0 / 10.0, dt))

        num_hands = 0
        hand_samples = []

        if results.multi_hand_landmarks:
            num_hands = len(results.multi_hand_landmarks)
            data["hands"] = num_hands

            do_draw = not self.headless

            # Collect grip points (+ optional handedness label)
            for idx, hand_landmarks in enumerate(results.multi_hand_landmarks):
                if do_draw:
                    self.drawing_utils.draw_landmarks(
                        frame,
                        hand_landmarks,
                        hands.HAND_CONNECTIONS,
                        self.drawing_utils.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=4),
                        self.drawing_utils.DrawingSpec(color=(0, 200, 0), thickness=2),
                    )

                grip_x, grip_y, grip_z = self.get_grip_point(hand_landmarks)
                hand_label = ""
                if results.multi_handedness and idx < len(results.multi_handedness):
                    classification = results.multi_handedness[idx].classification
                    if classification:
                        hand_label = str(classification[0].label).lower()

                hand_samples.append({"x": grip_x, "y": grip_y, "z": grip_z, "label": hand_label})

                if do_draw:
                    grip_pt = (int(grip_x * w), int(grip_y * h))
                    cv2.circle(frame, grip_pt, 10, (255, 255, 0), -1)
                    cv2.circle(frame, grip_pt, 13, (255, 255, 255), 2)

            # Process 2 hands
            if num_hands >= 2:
                first = hand_samples[0]
                second = hand_samples[1]

                left_hand = None
                right_hand = None
                first_label = first["label"]
                second_label = second["label"]

                if {first_label, second_label} == {"left", "right"}:
                    if first_label == "left":
                        left_hand = first
                        right_hand = second
                    else:
                        left_hand = second
                        right_hand = first
                else:
                    # Stable fallback by X coordinate
                    if first["x"] < second["x"]:
                        left_hand = first
                        right_hand = second
                    else:
                        left_hand = second
                        right_hand = first

                left_x, left_y, left_z = float(left_hand["x"]), float(left_hand["y"]), float(left_hand["z"])
                right_x, right_y, right_z = float(right_hand["x"]), float(right_hand["y"]), float(right_hand["z"])

                # Reset filters when reacquiring 2 hands
                if not self._had_two_hands_last:
                    self.of_left_x.reset(left_x)
                    self.of_left_y.reset(left_y)
                    self.of_right_x.reset(right_x)
                    self.of_right_y.reset(right_y)
                    self.of_left_z.reset(left_z)
                    self.of_right_z.reset(right_z)

                    self.kf_left_x.reset(left_x)
                    self.kf_left_y.reset(left_y)
                    self.kf_right_x.reset(right_x)
                    self.kf_right_y.reset(right_y)
                    angle_meas0 = math.atan2((right_y - left_y), (right_x - left_x))
                    self._last_angle_unwrapped = angle_meas0
                    self.kf_angle.reset(angle_meas0)
                    depth_norm0 = max(0.0, min(1.0, 0.5 + ((left_z + right_z) * 0.5) * self.depth_scale))
                    self.kf_depth.reset(depth_norm0)

                self._had_two_hands_last = True

                # One Euro smoothing at source points
                left_x = self.of_left_x.update(left_x, dt)
                left_y = self.of_left_y.update(left_y, dt)
                right_x = self.of_right_x.update(right_x, dt)
                right_y = self.of_right_y.update(right_y, dt)
                left_z = self.of_left_z.update(left_z, dt)
                right_z = self.of_right_z.update(right_z, dt)

                # Kalman-filtered hand positions
                lx = self.kf_left_x.update(left_x, dt)
                ly = self.kf_left_y.update(left_y, dt)
                rx = self.kf_right_x.update(right_x, dt)
                ry = self.kf_right_y.update(right_y, dt)

                # Derived values from filtered endpoints
                dx = rx - lx
                dy = ry - ly
                mid_x = (lx + rx) / 2.0
                mid_y = (ly + ry) / 2.0

                # Angle with unwrap to avoid jumps
                angle_meas = math.atan2(dy, dx)
                angle_unwrapped = unwrap_angle_rad(self._last_angle_unwrapped, angle_meas)
                self._last_angle_unwrapped = angle_unwrapped
                angle_f = self.kf_angle.update(angle_unwrapped, dt)
                angle_out = wrap_angle_rad(angle_f)

                # Depth normalization: distance field now carries normalized wheel depth (0..1)
                center_depth = (left_z + right_z) * 0.5
                depth_norm_meas = max(0.0, min(1.0, 0.5 + center_depth * self.depth_scale))
                depth_out = self.kf_depth.update(depth_norm_meas, dt)

                data["found"] = True
                data["mid_x"] = mid_x
                data["mid_y"] = mid_y
                data["angle"] = angle_out
                data["distance"] = depth_out

                if do_draw:
                    # Draw connection line
                    pt_left = (int(lx * w), int(ly * h))
                    pt_right = (int(rx * w), int(ry * h))
                    cv2.line(frame, pt_left, pt_right, (0, 255, 255), 4)

                    cv2.putText(
                        frame,
                        "L",
                        (pt_left[0] - 20, pt_left[1] - 20),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.7,
                        (0, 255, 0),
                        2,
                    )
                    cv2.putText(
                        frame,
                        "R",
                        (pt_right[0] + 10, pt_right[1] - 20),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.7,
                        (0, 255, 0),
                        2,
                    )

                    # Draw midpoint with angle indicator
                    mid_pt = (int(mid_x * w), int(mid_y * h))
                    angle_deg = math.degrees(angle_out)

                    if abs(angle_deg) < 10:
                        center_color = (0, 255, 0)  # Green = level
                    elif angle_deg > 0:
                        center_color = (0, 165, 255)  # Orange = tilt right
                    else:
                        center_color = (255, 165, 0)  # Cyan = tilt left

                    cv2.circle(frame, mid_pt, 25, center_color, -1)
                    cv2.circle(frame, mid_pt, 30, (255, 255, 255), 3)

                    # Tilt arrow
                    tilt_arrow_len = 35
                    perp_angle = angle_out - math.pi / 2
                    arrow_end = (
                        int(mid_pt[0] + tilt_arrow_len * math.cos(perp_angle)),
                        int(mid_pt[1] + tilt_arrow_len * math.sin(perp_angle)),
                    )
                    cv2.arrowedLine(frame, mid_pt, arrow_end, (255, 255, 255), 3, tipLength=0.4)

                    # Tilt bar
                    bar_y = h - 60
                    bar_center_x = w // 2
                    bar_width = 200
                    cv2.rectangle(
                        frame,
                        (bar_center_x - bar_width // 2, bar_y - 10),
                        (bar_center_x + bar_width // 2, bar_y + 10),
                        (50, 50, 50),
                        -1,
                    )
                    tilt_offset = int(angle_deg * bar_width / 90)
                    tilt_offset = max(-bar_width // 2, min(bar_width // 2, tilt_offset))
                    cv2.circle(frame, (bar_center_x + tilt_offset, bar_y), 8, center_color, -1)
                    cv2.putText(
                        frame,
                        f"{angle_deg:+.0f}deg",
                        (bar_center_x - 25, bar_y + 25),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        (200, 200, 200),
                        1,
                    )
            else:
                self._had_two_hands_last = False
                self._last_angle_unwrapped = None

        self.calculate_fps()

        if not self.headless:
            # Status bar
            cv2.rectangle(frame, (0, 0), (w, 80), (30, 30, 30), -1)

            if data["found"]:
                status = "2 HANDS DETECTED - OK!"
                color = (0, 255, 0)
            elif num_hands == 1:
                status = "Only 1 hand - Show BOTH hands!"
                color = (0, 255, 255)
            else:
                status = "No hands - Show both hands!"
                color = (0, 0, 255)

            cv2.putText(frame, status, (20, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.9, color, 2)
            cv2.putText(
                frame,
                f"Hands: {num_hands} | FPS: {self.fps:.1f} | Scale: {self.inference_scale:.2f}",
                (20, 65),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (200, 200, 200),
                1,
            )

            # Tracking info
            if data["found"]:
                info_x = w - 200
                cv2.putText(
                    frame,
                    f"X: {data['mid_x']:.2f}",
                    (info_x, 35),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (100, 255, 255),
                    1,
                )
                cv2.putText(
                    frame,
                    f"Y: {data['mid_y']:.2f}",
                    (info_x, 55),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (100, 255, 255),
                    1,
                )
                cv2.putText(
                    frame,
                    f"Depth: {data['distance']:.2f}",
                    (info_x + 80, 35),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (255, 100, 255),
                    1,
                )
                cv2.putText(
                    frame,
                    f"Angle: {math.degrees(data['angle']):.0f}°",
                    (info_x + 80, 55),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (255, 100, 255),
                    1,
                )

            # Instructions
            cv2.rectangle(frame, (0, h - 40), (w, h), (30, 30, 30), -1)
            cv2.putText(
                frame,
                "Q: Quit | Rotate wheel to steer | Push forward throttle | Pull back brake",
                (20, h - 15),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (200, 200, 200),
                1,
            )

        return frame, data

    def send_data(self, data):
        """Send tracking data as JSON over UDP."""
        try:
            payload = normalize_tracking_packet(data)
        except (TypeError, ValueError) as err:
            if not self.headless:
                print(f"Invalid tracking payload: {err}")
            return

        try:
            message = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.sock.sendto(message, self.godot_address)
        except (TypeError, ValueError, UnicodeEncodeError, OSError) as e:
            if not self.headless:
                print(f"UDP send error: {e}")

    def run(self):
        """Main tracking loop."""
        print("\n" + "=" * 60)
        print("  GRIDRUNNER - Hand Tracker Server v2 (CPU-optimized)")
        print("=" * 60)
        print(f"  ✓ Sending data to UDP {self.godot_address}")
        print(f"  ✓ Camera request: {self.frame_width}x{self.frame_height} @ {self.camera_fps} FPS")
        print(f"  ✓ Target FPS: {self.target_fps}")
        print(f"  ✓ Inference scale: {self.inference_scale:.2f} (adaptive={self.adaptive_scale})")
        print(f"  ✓ Model complexity: {self.model_complexity}")
        print(f"  ✓ Mode: {'Headless' if self.headless else 'GUI'}")
        print("")
        if not self.headless:
            print("  INSTRUCTIONS:")
            print("  1. Show BOTH hands to camera")
            print("  2. Yellow dots = grip points (thumb/index)")
            print("  3. Pink dot = midpoint")
            print("  4. Press Q to quit")
        print("=" * 60 + "\n")

        if not self.headless:
            cv2.namedWindow("Hand Tracker", cv2.WINDOW_NORMAL)
            cv2.resizeWindow("Hand Tracker", 800, 600)

        while self.running:
            if self._stop_requested():
                print("Stop flag detected. Shutting down tracker...")
                break

            frame = self._get_latest_frame()
            if frame is None:
                time.sleep(0.001)
                continue

            self.frame_count += 1
            frame, data = self.process_frame(frame)
            self.send_data(data)

            if not self.headless:
                cv2.imshow("Hand Tracker", frame)

                key = cv2.waitKey(1) & 0xFF
                if key == ord("q") or key == 27:
                    break

                try:
                    if cv2.getWindowProperty("Hand Tracker", cv2.WND_PROP_VISIBLE) < 1:
                        break
                except cv2.error as err:
                    print(f"Window query error: {err}")
                    break

        self.cleanup()

    def cleanup(self):
        """Clean up resources."""
        self.running = False
        if self._capture_thread and self._capture_thread.is_alive():
            self._capture_thread.join(timeout=1.0)
        if self.cap:
            self.cap.release()
        cv2.destroyAllWindows()
        self.sock.close()
        if self.stop_file and os.path.exists(self.stop_file):
            try:
                os.remove(self.stop_file)
            except OSError as err:
                if not self.headless:
                    print(f"Warning: failed to remove stop flag '{self.stop_file}': {err}")
        print("\nTracker stopped.")


def parse_args(argv):
    parser = argparse.ArgumentParser(description="GridRunner hand tracker (CPU optimized).")
    parser.add_argument("camera_index", nargs="?", type=int, default=None)
    parser.add_argument("--camera", type=int, default=None, help="Camera index override.")
    parser.add_argument("--headless", action="store_true", help="Disable OpenCV preview window.")
    parser.add_argument("--width", type=int, default=640, help="Camera width (default: 640).")
    parser.add_argument("--height", type=int, default=480, help="Camera height (default: 480).")
    parser.add_argument("--fps", type=int, default=60, help="Requested camera FPS (default: 60).")
    parser.add_argument("--target-fps", type=int, default=60, help="Adaptive scaling target FPS (default: 60).")
    parser.add_argument("--scale", type=float, default=0.6, help="Inference scale factor 0.35..1.0 (default: 0.6).")
    parser.add_argument("--model-complexity", type=int, choices=[0, 1], default=0, help="MediaPipe model complexity.")
    parser.add_argument("--confidence", type=float, default=0.5, help="Detection confidence (default: 0.5).")
    parser.add_argument("--tracking-confidence", type=float, default=0.4, help="Tracking confidence (default: 0.4).")
    parser.add_argument("--no-adaptive-scale", action="store_true", help="Disable adaptive inference scaling.")
    parser.add_argument("--stop-file", type=str, default=None, help="Path to a stop-flag file for graceful shutdown.")
    return parser.parse_args(argv)


if __name__ == "__main__":
    args = parse_args(sys.argv[1:])
    camera_idx = args.camera if args.camera is not None else (args.camera_index if args.camera_index is not None else 0)

    server = HandTrackerServer(
        udp_port=5555,
        camera_index=camera_idx,
        headless=args.headless,
        frame_width=args.width,
        frame_height=args.height,
        camera_fps=args.fps,
        inference_scale=args.scale,
        model_complexity=args.model_complexity,
        min_detection_confidence=args.confidence,
        min_tracking_confidence=args.tracking_confidence,
        target_fps=args.target_fps,
        adaptive_scale=not args.no_adaptive_scale,
        stop_file=args.stop_file,
    )
    server.run()
