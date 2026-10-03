"""STM32 newline-delimited quaternion packets over UART / USB CDC (115200).
Pi owns freshness and turn confirmation; phone flags never authorize heading.
"""
import json
import math
import threading
import time


class STM32IMUReceiverThread(threading.Thread):
    def __init__(self, port, baudrate=115200, timeout_s=0.5, clock=time.monotonic):
        super().__init__(name='STM32IMUReceiverThread', daemon=True)
        self.port, self.baudrate = port, baudrate
        self.timeout_s, self.clock = timeout_s, clock
        self._stop_event = threading.Event()
        self._lock = threading.Lock()
        self._sample = None
        self._received = float('-inf')
        self._sequence = -1
        self._timestamp = -1

    def feed(self, line):
        """Validate one complete packet. Quaternion is [w,x,y,z], yaw=true north."""
        try:
            if len(line) > 1024:
                return False
            j = json.loads(line)
            if not isinstance(j, dict) or j.get('type') != 'imu' or j.get('version') != 1:
                return False
            seq, stamp = j['sequence'], j['timestamp_ms']
            if type(seq) is not int or seq < 0 or type(stamp) is not int or stamp < 0:
                return False
            if type(j['calibrated']) is not bool:
                return False
            q = j['quaternion']
            if not isinstance(q, list) or len(q) != 4 or any(
                    type(x) not in (float, int) or not math.isfinite(x) for x in q):
                return False
            norm = math.sqrt(sum(x*x for x in q))
            if not .95 <= norm <= 1.05:
                return False
            w, x, y, z = [v / norm for v in q]
            heading = math.degrees(math.atan2(2*(w*z+x*y), 1-2*(y*y+z*z))) % 360
            pitch = math.degrees(math.asin(max(-1, min(1, 2*(w*y-z*x)))))
            roll = math.degrees(math.atan2(2*(w*x+y*z), 1-2*(x*x+y*y)))
            with self._lock:
                if seq <= self._sequence or stamp <= self._timestamp:
                    return False
                self._sample = dict(stm32_calibrated=j['calibrated'],
                    stm32_heading=heading, stm32_pitch=pitch, stm32_roll=roll,
                    stm32_quaternion=[w, x, y, z])
                self._sequence, self._timestamp = seq, stamp
                self._received = self.clock()
            return True
        except (ValueError, TypeError, KeyError, OverflowError):
            return False

    def invalidate(self):
        with self._lock:
            self._sample = None
            self._received = float('-inf')
            self._sequence = self._timestamp = -1

    def snapshot(self):
        with self._lock:
            fresh = self._sample is not None and self.clock() - self._received <= self.timeout_s
            if not fresh:
                return {'stm32_ok': False, 'stm32_calibrated': False,
                        'stm32_heading': None, 'stm32_pitch': None, 'stm32_roll': None,
                        'stm32_quaternion': None}
            return dict(self._sample, stm32_ok=True)

    def compare(self, target_bearing, tolerance=15):
        s = self.snapshot()
        if (not s['stm32_ok'] or not s['stm32_calibrated'] or
                type(target_bearing) not in (int, float) or
                not math.isfinite(target_bearing) or not 0 <= target_bearing < 360):
            return {'heading_valid': False, 'turn_confirmed': False, 'heading_error': None}
        error = (target_bearing - s['stm32_heading'] + 180) % 360 - 180
        return {'heading_valid': True, 'turn_confirmed': abs(error) <= tolerance,
                'heading_error': error}

    def run(self):
        import serial
        while not self._stop_event.is_set():
            try:
                with serial.Serial(self.port, self.baudrate, timeout=.1) as device:
                    device.reset_input_buffer()
                    self.invalidate()
                    pending = bytearray()
                    while not self._stop_event.is_set():
                        chunk = device.read(256)
                        pending.extend(chunk)
                        while b'\n' in pending:
                            line, _, rest = pending.partition(b'\n')
                            pending = bytearray(rest)
                            self.feed(line)
                        if len(pending) > 1024:
                            raise ValueError('Oversize serial frame')
            except (serial.SerialException, OSError, ValueError):
                self.invalidate()
                self._stop_event.wait(1)
        self.invalidate()

    def stop(self):
        self._stop_event.set()
