import asyncio
import time
import unittest
from unittest.mock import AsyncMock, patch
from aiohttp.test_utils import TestClient, TestServer
from server import create_app, DecisionManager, SIM_KEY

TOKEN = 'test-token-only-01234567890123456789'

class ProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.app = create_app(TOKEN)
        self.client = TestClient(TestServer(self.app))
        await self.client.start_server()
        self.headers = {'Authorization': f'Bearer {TOKEN}'}

    async def asyncTearDown(self):
        await self.client.close()

    async def test_auth_required(self):
        response = await self.client.get('/device/status')
        self.assertEqual(response.status, 401)
        response = await self.client.get('/device/status', headers=self.headers)
        self.assertTrue((await response.json())['demo'])

    async def test_audio_check_requires_auth_and_real_speech_engine(self):
        response = await self.client.post('/audio/test', json={})
        self.assertEqual(response.status, 401)
        response = await self.client.post('/audio/test', json={}, headers=self.headers)
        self.assertEqual(response.status, 503)
        sim = self.app[SIM_KEY]
        sim.decision.voice = True
        sim.decision.say = AsyncMock(return_value=True)
        with patch('server.shutil.which', return_value='/fake/espeak-ng'):
            response = await self.client.post('/audio/test', json={}, headers=self.headers)
        self.assertEqual(response.status, 200)
        self.assertIn('Kiểm tra âm thanh kính', sim.decision.say.call_args.args[0])

    async def test_phone_acknowledges_silence_before_pi_speech(self):
        ws = await self.client.ws_connect('/ws', headers=self.headers)
        sim = self.app[SIM_KEY]
        alert = asyncio.create_task(sim.alert('Cảnh báo', {'message': 'Cảnh báo'}))
        while True:
            msg = await ws.receive_json()
            if msg['type'] == 'hazard':
                break
        self.assertEqual(sim.decision.last_output, '')
        await ws.send_json({'type': 'audio_yielded', 'hazard_id': msg['hazard_id']})
        await alert
        self.assertEqual(sim.decision.last_output, 'Cảnh báo')
        self.assertTrue(sim.yield_ack.done())
        await ws.close()

    async def test_long_speech_renews_phone_silence_until_finished(self):
        sim = self.app[SIM_KEY]
        frames = []
        async def broadcast(data):
            frames.append(data)
        sim.broadcast = broadcast
        finished = asyncio.get_running_loop().create_future()
        async def wait_spoken(_):
            await finished
        sim.decision.wait_spoken = wait_spoken
        hazard_id = await sim.alert('Cảnh báo dài', {'message': 'Cảnh báo dài'})
        await asyncio.sleep(1.05)
        self.assertTrue(any(frame['type'] == 'hazard_hold' and
            frame['hazard_id'] == hazard_id for frame in frames))
        self.assertFalse(any(frame['type'] == 'hazard_clear' for frame in frames))
        finished.set_result(None)
        await sim.clear_task
        self.assertEqual(frames[-1]['type'], 'hazard_clear')

    def snapshot(self, revision=1, state='navigating'):
        return {'protocol': 1, 'session_id': 'journey-a', 'revision': revision,
            'state': state, 'route': {'id': 'route-a', 'points': [[106,10],[106.01,10.01]], 'demo': False}}

    async def test_revision_and_validation(self):
        for body, expected in [(self.snapshot(2), 200), (self.snapshot(1), 409),
                               ({'state': 'navigating'}, 400), (self.snapshot(2), 200)]:
            response = await self.client.post('/navigation/state', json=body, headers=self.headers)
            self.assertEqual(response.status, expected)
        body = self.snapshot(3); body['route']['demo'] = True
        response = await self.client.post('/navigation/state', json=body, headers=self.headers)
        self.assertEqual(response.status, 400)

    async def test_ws_heartbeat_instruction_pause_and_replay(self):
        await self.client.post('/navigation/state', json=self.snapshot(), headers=self.headers)
        ws = await self.client.ws_connect('/ws', headers=self.headers)
        await ws.send_json({'type': 'ping'})
        while (await ws.receive_json())['type'] != 'pong':
            pass
        m = {'type': 'navigation_instruction', 'session_id': 'journey-a', 'revision': 1,
             'route_id': 'route-a', 'sequence': 1, 'step_index': 1, 'distance_m': 35,
             'valid_for_ms': 3000, 'gps_valid': True, 'text': 'Rẽ phải', 'action': 'turn_right'}
        await ws.send_json(m)
        await asyncio.sleep(.02)
        sim = self.app[SIM_KEY]
        self.assertEqual(sim.seq, 1)
        self.assertGreater(sim.decision.navigation_until, time.monotonic())
        await ws.send_json(dict(m, sequence=0, text='old'))
        await asyncio.sleep(.02)
        self.assertEqual(sim.seq, 1)
        await self.client.post('/navigation/state', json=self.snapshot(2, 'paused'), headers=self.headers)
        await ws.send_json(dict(m, sequence=2))
        await asyncio.sleep(.02)
        self.assertEqual(sim.decision.navigation_until, 0)
        await ws.close()

    async def test_settings_bounds(self):
        response = await self.client.post('/settings', headers=self.headers,
            json={'warning_level': 'normal', 'volume': 8, 'speech_rate': .5, 'vibration': True})
        self.assertEqual(response.status, 400)

    async def test_hazard_preempts_navigation_and_ttl_expires(self):
        d = DecisionManager()
        await d.say('route')
        await d.say('STOP', urgent=True)
        await d.say('turn right')
        self.assertEqual(d.last_output, 'STOP')
        d.blocked_until = 0
        d.navigation_until = time.monotonic() - 1
        await d.watchdog()
        self.assertEqual(d.navigation_until, 0)
        self.assertIn('tạm dừng', d.last_output)

    async def test_pi_does_not_speak_turn_guidance(self):
        d = DecisionManager()
        m = {'route_id': 'route-a', 'step_index': 1, 'distance_m': 8,
             'valid_for_ms': 3000, 'gps_valid': True, 'text': 'Rẽ phải', 'action': 'turn_right'}
        await d.instruction(m)
        self.assertEqual(d.last_output, '')
        self.assertGreater(d.navigation_until, time.monotonic())

    async def test_hazard_tells_phone_before_speaking_then_clears(self):
        sim = self.app[SIM_KEY]
        sim.decision.speech_ms = lambda text: 30
        order = []
        original_say, original_broadcast = sim.decision.say, sim.broadcast

        async def tracking_say(text, urgent=False):
            order.append('speak')
            return await original_say(text, urgent)

        async def tracking_broadcast(data):
            order.append(data['type'])
            return await original_broadcast(data)
        sim.decision.say = tracking_say
        sim.broadcast = tracking_broadcast
        ws = await self.client.ws_connect('/ws', headers=self.headers)
        response = await self.client.post('/demo/hazard', headers=self.headers)
        hazard_id = (await response.json())['hazard_id']
        hazard = clear = None
        while clear is None:
            msg = await asyncio.wait_for(ws.receive_json(), 2)
            if msg['type'] == 'hazard':
                hazard = msg
            elif msg['type'] == 'hazard_clear':
                clear = msg
        self.assertEqual(hazard['hazard_id'], hazard_id)
        self.assertGreaterEqual(hazard['hold_ms'], 2000)
        self.assertLessEqual(hazard['hold_ms'], 8000)
        self.assertEqual(clear['hazard_id'], hazard_id)
        events = [e for e in order if e in {'hazard', 'speak', 'hazard_clear'}]
        self.assertEqual(events, ['hazard', 'speak', 'hazard_clear'])
        await ws.close()

    async def test_newer_hazard_owns_the_silence_window(self):
        sim = self.app[SIM_KEY]
        sim.decision.speech_ms = lambda text: 30
        sent = []

        async def capture(data):
            sent.append(data)
        sim.broadcast = capture
        first = await sim.alert('một', {'message': 'một'})
        second = await sim.alert('hai', {'message': 'hai'})
        await asyncio.sleep(.1)
        clears = [m['hazard_id'] for m in sent if m['type'] == 'hazard_clear']
        self.assertEqual(clears, [second])
        self.assertNotIn(first, clears)


if __name__ == '__main__':
    unittest.main()
