"""SecondSight protocol reference / SIMULATOR, not a perception stack.
Run: SECONDSIGHT_TOKEN=<random secret> python server.py
Telemetry is explicitly marked demo. No camera/video processing occurs here.
"""
import asyncio
import contextlib
import json
import os
import secrets
import shutil
import time
from aiohttp import web, WSMsgType
from stm32_imu import STM32IMUReceiverThread


class DecisionManager:
    """Pi speaks hazards and safety status only; the phone speaks turn guidance.

    Navigation frames are still validated and expire independently (TTL) and are
    used for STM32 turn confirmation, but are never read aloud here, so the two
    devices cannot both announce the same turn.
    """
    def __init__(self, voice=False, imu=None):
        self.imu = imu
        self.turn_state = {"heading_valid": False, "turn_confirmed": False, "heading_error": None}
        self.voice = voice
        self.process = None
        self.blocked_until = 0.0
        self.navigation_until = 0.0
        self.last_instruction = None
        self.last_output = ''
        self.volume = 0.8
        self.rate = 0.5

    async def say(self, text, urgent=False):
        if urgent:
            self.blocked_until = time.monotonic() + 6
            await self.silence()
        elif time.monotonic() < self.blocked_until:
            return False
        elif self.process and self.process.returncode is None:
            return False  # do not continually interrupt an ongoing route instruction
        self.last_output = text
        print(f"{'HAZARD' if urgent else 'AUDIO'}: {text}", flush=True)
        if self.voice and shutil.which('espeak-ng'):
            self.process = await asyncio.create_subprocess_exec(
                'espeak-ng', '-v', 'vi', '-a', str(round(self.volume * 100)),
                '-s', str(round(100 + self.rate * 180)), text,
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        return True

    async def silence(self):
        if self.process and self.process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                self.process.terminate()
            await self.process.wait()
        self.process = None

    def speech_ms(self, text):
        """Estimated espeak-ng duration for [text] at the configured rate."""
        words_per_minute = 100 + self.rate * 180
        return round(len(text.split()) / words_per_minute * 60000) + 300

    def hold_ms(self, text):
        """How long the phone must stay silent: speech + margin, 2-8 s."""
        return max(2000, min(8000, self.speech_ms(text) + 1500))

    async def wait_spoken(self, text):
        """Wait until the current utterance has finished playing."""
        process = self.process
        if process is not None:
            with contextlib.suppress(ProcessLookupError):
                await process.wait()
        else:
            # Text-only simulator: pretend to speak for the estimated time.
            await asyncio.sleep(self.speech_ms(text) / 1000)

    async def instruction(self, msg):
        self.turn_state = {"heading_valid": False, "turn_confirmed": False, "heading_error": None}
        if self.imu and msg.get('gps_valid') and msg.get('action') != 'hold':
            self.turn_state = self.imu.compare(msg.get('target_bearing'))
            self.turn_state['turn_confirmed'] = (self.turn_state['turn_confirmed']
                and msg.get('action') in {'turn_left', 'turn_right', 'u_turn', 'roundabout'}
                and 0 <= msg.get('distance_m', float('inf')) <= 12)
        if not msg.get('gps_valid') or msg.get('action') == 'hold':
            self.navigation_until = 0
            # Never silence a hazard because navigation has become invalid.
            if time.monotonic() >= self.blocked_until:
                await self.silence()
            return
        self.navigation_until = time.monotonic() + min(msg['valid_for_ms'], 3000) / 1000
        # Turn guidance is spoken by the phone only (see class docstring).

    async def watchdog(self):
        if self.navigation_until and time.monotonic() > self.navigation_until:
            self.navigation_until = 0
            if time.monotonic() >= self.blocked_until:
                await self.silence()
                await self.say('Chỉ dẫn đường đang tạm dừng.')


class PiSimulator:
    def __init__(self, token, voice=False, imu=None):
        self.token = token
        self.peers = set()
        self.state = {'state': 'idle', 'revision': -1, 'session_id': None}
        self.seq = -1
        self.settings = {}
        self.imu = imu
        self.decision = DecisionManager(voice, imu)
        self.task = None
        self.last_ping = time.monotonic()
        self.hazard_seq = 0
        self.active_hazard = None
        self.clear_task = None
        self.yield_ack = None

    async def alert(self, text, payload):
        """Raise a hazard: tell the phone to go silent FIRST, then speak.

        The phone cancels its own TTS on `hazard` and stays silent for
        `hold_ms` (fallback TTL) or until the matching `hazard_clear`.
        """
        self.hazard_seq += 1
        hazard_id = f'h-{self.hazard_seq}'
        self.active_hazard = hazard_id
        ack = self.yield_ack = asyncio.get_running_loop().create_future()
        await self.broadcast({'type': 'hazard', 'hazard_id': hazard_id,
            'hold_ms': self.decision.hold_ms(text), **payload})
        if self.peers:
            # Bound the handshake: a missing phone must never delay safety
            # speech indefinitely. New app versions acknowledge TTS stop.
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(asyncio.shield(ack), .2)
        await self.decision.say(text, urgent=True)
        if self.clear_task and not self.clear_task.done():
            self.clear_task.cancel()
        self.clear_task = asyncio.create_task(self._clear_after(hazard_id, text))
        return hazard_id

    async def _clear_after(self, hazard_id, text):
        speech = asyncio.create_task(self.decision.wait_spoken(text))
        try:
            while not speech.done():
                await asyncio.wait({speech}, timeout=1)
                if not speech.done() and hazard_id == self.active_hazard:
                    # Renew silence throughout long speech; do not rely only
                    # on an estimated duration or release on an old clear.
                    await self.broadcast({'type': 'hazard_hold',
                        'hazard_id': hazard_id, 'hold_ms': 3000})
            await speech
            if hazard_id == self.active_hazard:
                self.active_hazard = None
                await self.broadcast({'type': 'hazard_clear', 'hazard_id': hazard_id})
        finally:
            if not speech.done():
                speech.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await speech

    async def broadcast(self, data):
        for peer in list(self.peers):
            if not peer.closed:
                with contextlib.suppress(ConnectionError, RuntimeError):
                    await peer.send_json(data)

    async def telemetry(self):
        while True:
            await self.broadcast({'type': 'device_status', 'demo': True,
                'yolo_fps': 18.4, 'cpu_temp': 62.0, 'battery_percent': 76,
                'camera_ok': True, 'lidar_ok': True,
                'stm32_source': 'serial' if self.imu else 'unavailable',
                **(self.imu.snapshot() if self.imu else {
                    'stm32_ok': False, 'stm32_calibrated': False, 'stm32_heading': None})})
            await self.decision.watchdog()
            if time.monotonic() - self.last_ping > 6:
                for ws in list(self.peers):
                    await ws.close(code=1001, message=b'heartbeat expired')
            await asyncio.sleep(1)

    async def ws(self, request):
        if self.peers:
            raise web.HTTPConflict(text='Only one controller at a time')
        ws = web.WebSocketResponse(max_msg_size=262144, heartbeat=10)
        await ws.prepare(request)
        self.peers.add(ws)
        self.last_ping = time.monotonic()
        try:
            async for frame in ws:
                if frame.type != WSMsgType.TEXT:
                    continue
                try:
                    msg = json.loads(frame.data)
                    if not isinstance(msg, dict):
                        continue
                    if msg.get('type') == 'audio_yielded':
                        if (msg.get('hazard_id') == self.active_hazard and
                                self.yield_ack and not self.yield_ack.done()):
                            self.yield_ack.set_result(True)
                    elif msg.get('type') == 'ping':
                        self.last_ping = time.monotonic()
                        await ws.send_json({'type': 'pong'})
                    elif msg.get('type') == 'navigation_instruction':
                        if not valid_instruction(msg):
                            await ws.send_json({'type': 'system_error', 'message': 'Malformed navigation frame'})
                            continue
                        if (self.state['state'] != 'navigating'
                            or msg.get('session_id') != self.state['session_id']
                            or msg.get('revision') != self.state['revision']
                            or msg.get('route_id') != (self.state.get('route') or {}).get('id')
                            or msg['sequence'] <= self.seq):
                            continue
                        self.seq = msg['sequence']
                        await self.decision.instruction(msg)
                        await ws.send_json({'type': 'turn_status', 'sequence': self.seq,
                            **self.decision.turn_state})
                except (ValueError, TypeError, KeyError):
                    await ws.send_json({'type': 'system_error', 'message': 'Invalid JSON'})
        finally:
            self.peers.discard(ws)
            self.decision.navigation_until = 0
            if time.monotonic() >= self.decision.blocked_until:
                await self.decision.silence()
                await self.decision.say('Mất kết nối điện thoại. Chỉ dẫn đường đang tạm dừng. Đây là Pi mô phỏng.')
        return ws

    async def navigation(self, request):
        try:
            data = await request.json()
            assert isinstance(data, dict)
            assert data.get('protocol') == 1
            assert data.get('state') in {'idle', 'ready', 'navigating', 'paused', 'arrived'}
            assert isinstance(data.get('session_id'), str) and 1 <= len(data['session_id']) <= 100
            assert type(data.get('revision')) is int and data['revision'] >= 0
            if data['state'] == 'navigating':
                assert isinstance(data.get('route'), dict)
                assert isinstance(data['route'].get('id'), str)
                assert len(data['route'].get('points', [])) >= 2
                assert data['route'].get('demo') is not True
        except (ValueError, TypeError, AssertionError):
            raise web.HTTPBadRequest(text='Invalid navigation snapshot')
        if data['session_id'] == self.state['session_id'] and data['revision'] < self.state['revision']:
            raise web.HTTPConflict(text='Stale revision')
        if data['session_id'] != self.state['session_id']:
            self.seq = -1
        changed = (data['state'], data['session_id'], data['revision']) != (
            self.state['state'], self.state['session_id'], self.state['revision'])
        self.state = data
        if changed:
            self.decision.last_instruction = None
        if data['state'] != 'navigating':
            self.decision.navigation_until = 0
            if time.monotonic() >= self.decision.blocked_until:
                await self.decision.silence()
                if changed and data['state'] == 'arrived':
                    await self.decision.say('Đã đến điểm đến.')
        return web.json_response({'ok': True, 'revision': data['revision']})

    async def configure(self, request):
        try:
            j = await request.json()
            assert isinstance(j, dict)
            assert j['warning_level'] in {'low', 'normal', 'detailed'}
            assert type(j['vibration']) is bool
            assert isinstance(j['volume'], (int, float)) and 0 <= j['volume'] <= 1
            assert isinstance(j['speech_rate'], (int, float)) and .2 <= j['speech_rate'] <= .8
        except (ValueError, KeyError, TypeError, AssertionError):
            raise web.HTTPBadRequest(text='Invalid settings')
        self.settings = j
        self.decision.volume, self.decision.rate = j['volume'], j['speech_rate']
        return web.json_response({'ok': True})

    async def audio_test(self, request):
        if self.active_hazard:
            raise web.HTTPConflict(text='Safety alert in progress')
        if not self.decision.voice or not shutil.which('espeak-ng'):
            raise web.HTTPServiceUnavailable(text='Pi speech output unavailable')
        await self.alert('Kiểm tra âm thanh kính. Bạn có nghe rõ không?', {
            'severity': 'info', 'hazard_class': 'audio_test',
            'message': 'Đang thử âm thanh kính.'})
        return web.json_response({'ok': True})

    async def hazard(self, request):
        # Explicit demo endpoint. Production sensor fusion calls alert() directly.
        hazard_id = await self.alert('Mô phỏng. Dừng lại — có mép hụt phía trước.', {
            'demo': True, 'hazard_class': 'drop_off', 'distance_m': 1.2,
            'severity': 'stop', 'confidence': .91,
            'message': 'Mô phỏng: có mép hụt phía trước.'})
        return web.json_response({'ok': True, 'demo': True, 'hazard_id': hazard_id})


def valid_instruction(j):
    return (type(j.get('sequence')) is int and j['sequence'] >= 0
        and type(j.get('step_index')) is int and j['step_index'] >= 0
        and type(j.get('distance_m')) is int and j['distance_m'] >= 0
        and type(j.get('valid_for_ms')) is int and 0 < j['valid_for_ms'] <= 3000
        and type(j.get('gps_valid')) is bool
        and isinstance(j.get('text'), str) and len(j['text']) <= 1000
        and j.get('action') in {'hold', 'continue', 'turn_left', 'turn_right', 'roundabout', 'u_turn', 'arrive'})


SIM_KEY = web.AppKey('sim', PiSimulator)

def create_app(token, voice=False, imu=None):
    if len(token) < 24:
        raise ValueError('Use a random pairing token of at least 24 characters')
    sim = PiSimulator(token, voice, imu)

    @web.middleware
    async def auth(request, handler):
        if not secrets.compare_digest(request.headers.get('Authorization', ''), f'Bearer {token}'):
            raise web.HTTPUnauthorized(text='Pairing token required')
        return await handler(request)

    app = web.Application(middlewares=[auth], client_max_size=2 * 1024 * 1024)
    app[SIM_KEY] = sim
    app.router.add_get('/ws', sim.ws)
    app.router.add_post('/navigation/state', sim.navigation)
    app.router.add_post('/settings', sim.configure)
    app.router.add_post('/demo/hazard', sim.hazard)
    app.router.add_post('/audio/test', sim.audio_test)

    async def status(_):
        return web.json_response({'demo': True, 'state': sim.state['state']})
    app.router.add_get('/device/status', status)

    async def start(_):
        if sim.imu:
            sim.imu.start()
        sim.task = asyncio.create_task(sim.telemetry())
    async def stop(_):
        if sim.imu:
            sim.imu.stop()
            await asyncio.to_thread(sim.imu.join, 2)
        sim.task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await sim.task
        if sim.clear_task and not sim.clear_task.done():
            sim.clear_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await sim.clear_task
        for ws in list(sim.peers):
            await ws.close()
        await sim.decision.silence()
    app.on_startup.append(start)
    app.on_shutdown.append(stop)
    return app

if __name__ == '__main__':
    token = os.environ.get('SECONDSIGHT_TOKEN', '')
    port = os.environ.get('SECONDSIGHT_IMU_PORT')
    imu = STM32IMUReceiverThread(port) if port else None
    app = create_app(token, os.environ.get('SECONDSIGHT_VOICE') == '1', imu)
    print('SIMULATOR ONLY. HTTP LAN: use a private hotspot. Production requires TLS.')
    web.run_app(app, host=os.environ.get('SECONDSIGHT_HOST', '0.0.0.0'), port=8765,
                access_log=None)  # never print credentials or URLs in access logs
