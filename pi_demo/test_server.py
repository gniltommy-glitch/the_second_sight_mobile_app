import asyncio
import time
import unittest
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

if __name__ == '__main__':
    unittest.main()
