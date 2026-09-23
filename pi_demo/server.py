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


class DecisionManager:
    """Local hazard interrupts route speech. Navigation expires independently."""
    def __init__(self, voice=False):
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

    async def instruction(self, msg):
        if not msg.get('gps_valid') or msg.get('action') == 'hold':
            self.navigation_until = 0
            # Never silence a hazard because navigation has become invalid.
            if time.monotonic() >= self.blocked_until:
                await self.silence()
            return
        self.navigation_until = time.monotonic() + min(msg['valid_for_ms'], 3000) / 1000
        key = (msg['route_id'], msg['step_index'], msg['distance_m'] < 20)
        if key != self.last_instruction and time.monotonic() >= self.blocked_until:
            if await self.say(f"{msg['distance_m']} mét. {msg['text']}"):
                self.last_instruction = key

    async def watchdog(self):
        if self.navigation_until and time.monotonic() > self.navigation_until:
            self.navigation_until = 0
            if time.monotonic() >= self.blocked_until:
                await self.silence()
                await self.say('Chỉ dẫn đường đang tạm dừng.')


class PiSimulator:
    def __init__(self, token, voice=False):
        self.token = token
        self.peers = set()
        self.state = {'state': 'idle', 'revision': -1, 'session_id': None}
        self.seq = -1
        self.settings = {}
        self.decision = DecisionManager(voice)
        self.task = None
        self.last_ping = time.monotonic()

    async def broadcast(self, data):
        for peer in list(self.peers):
            if not peer.closed:
                with contextlib.suppress(ConnectionError, RuntimeError):
                    await peer.send_json(data)

    async def telemetry(self):
        while True:
            await self.broadcast({'type': 'device_status', 'demo': True,
                'yolo_fps': 18.4, 'cpu_temp': 62.0, 'battery_percent': 76,
                'camera_ok': True, 'lidar_ok': True, 'imu_ok': True})
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
                    if msg.get('type') == 'ping':
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
            if not isinstance(data, dict): raise ValueError()
            if data.get('protocol') != 1: raise ValueError()
            if data.get('state') not in {'idle', 'ready', 'navigating', 'paused', 'arrived'}: raise ValueError()
            if not (isinstance(data.get('session_id'), str) and 1 <= len(data['session_id']) <= 100): raise ValueError()
            if not (type(data.get('revision')) is int and data['revision'] >= 0): raise ValueError()
            if data['state'] == 'navigating':
                if not isinstance(data.get('route'), dict): raise ValueError()
                if not isinstance(data['route'].get('id'), str): raise ValueError()
                if not (len(data['route'].get('points', [])) >= 2): raise ValueError()
                if data['route'].get('demo') is True: raise ValueError()
        except (ValueError, TypeError):
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
            if not isinstance(j, dict): raise ValueError()
            if j['warning_level'] not in {'low', 'normal', 'detailed'}: raise ValueError()
            if type(j['vibration']) is not bool: raise ValueError()
            if not (isinstance(j['volume'], (int, float)) and 0 <= j['volume'] <= 1): raise ValueError()
            if not (isinstance(j['speech_rate'], (int, float)) and .2 <= j['speech_rate'] <= .8): raise ValueError()
        except (ValueError, KeyError, TypeError):
            raise web.HTTPBadRequest(text='Invalid settings')
        self.settings = j
        self.decision.volume, self.decision.rate = j['volume'], j['speech_rate']
        return web.json_response({'ok': True})

    async def hazard(self, request):
        # Explicit demo endpoint. Production sensor fusion calls DecisionManager directly.
        await self.decision.say('Mô phỏng. Dừng lại — có mép hụt phía trước.', urgent=True)
        await self.broadcast({'type': 'hazard', 'demo': True, 'hazard_class': 'drop_off',
            'distance_m': 1.2, 'severity': 'stop', 'confidence': .91,
            'message': 'Mô phỏng: có mép hụt phía trước.'})
        return web.json_response({'ok': True, 'demo': True})


def valid_instruction(j):
    return (type(j.get('sequence')) is int and j['sequence'] >= 0
        and type(j.get('step_index')) is int and j['step_index'] >= 0
        and type(j.get('distance_m')) is int and j['distance_m'] >= 0
        and type(j.get('valid_for_ms')) is int and 0 < j['valid_for_ms'] <= 3000
        and type(j.get('gps_valid')) is bool
        and isinstance(j.get('text'), str) and len(j['text']) <= 1000
        and j.get('action') in {'hold', 'continue', 'turn_left', 'turn_right', 'roundabout', 'u_turn', 'arrive'})


SIM_KEY = web.AppKey('sim', PiSimulator)

def create_app(token, voice=False):
    if len(token) < 24:
        raise ValueError('Use a random pairing token of at least 24 characters')
    sim = PiSimulator(token, voice)

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

    async def status(_):
        return web.json_response({'demo': True, 'state': sim.state['state']})
    app.router.add_get('/device/status', status)

    async def start(_):
        sim.task = asyncio.create_task(sim.telemetry())
    async def stop(_):
        sim.task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await sim.task
        for ws in list(sim.peers):
            await ws.close()
        await sim.decision.silence()
    app.on_startup.append(start)
    app.on_shutdown.append(stop)
    return app

if __name__ == '__main__':
    token = os.environ.get('SECONDSIGHT_TOKEN', '')
    app = create_app(token, os.environ.get('SECONDSIGHT_VOICE') == '1')
    print('SIMULATOR ONLY. HTTP LAN: use a private hotspot. Production requires TLS.')
    web.run_app(app, host=os.environ.get('SECONDSIGHT_HOST', '0.0.0.0'), port=8765,
                access_log=None)  # never print credentials or URLs in access logs
