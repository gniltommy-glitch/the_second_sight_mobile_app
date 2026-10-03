import json
import math
import unittest
from stm32_imu import STM32IMUReceiverThread
from server import DecisionManager

class IMUTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.
        self.imu = STM32IMUReceiverThread('unused', clock=lambda: self.now)
    def packet(self, heading=359, calibrated=True, seq=1):
        a = math.radians(heading) / 2
        return json.dumps(dict(type='imu', version=1, sequence=seq, timestamp_ms=seq*50,
          calibrated=calibrated, quaternion=[math.cos(a),0,0,math.sin(a)]))
    def test_wraparound_and_expiry(self):
        self.assertTrue(self.imu.feed(self.packet()))
        result = self.imu.compare(1)
        self.assertTrue(result['turn_confirmed'])
        self.assertAlmostEqual(result['heading_error'], 2)
        self.now += .51
        self.assertFalse(self.imu.compare(1)['heading_valid'])
        self.assertIsNone(self.imu.snapshot()['stm32_heading'])
    def test_disconnect_uncalibrated_and_replay(self):
        self.assertTrue(self.imu.feed(self.packet(calibrated=False)))
        self.assertFalse(self.imu.compare(359)['turn_confirmed'])
        self.assertFalse(self.imu.feed(self.packet(calibrated=True)))
        self.imu.invalidate()
        self.assertFalse(self.imu.compare(0)['heading_valid'])
        self.assertTrue(self.imu.feed(self.packet(90)))
        self.assertFalse(self.imu.compare(180)['turn_confirmed'])
    def test_malformed_nonfinite_and_target(self):
        for line in ['{}', '[]', 'x', json.dumps(dict(type='imu', version=1,
            sequence=1, timestamp_ms=50, calibrated=True, quaternion=[float('nan'),0,0,0]))]:
            self.assertFalse(self.imu.feed(line))
        self.imu.feed(self.packet())
        for target in [None, float('nan'), 360, -1, True]:
            self.assertFalse(self.imu.compare(target)['heading_valid'])

class HazardTests(unittest.IsolatedAsyncioTestCase):
    async def test_imu_failure_never_silences_hazard(self):
        imu = STM32IMUReceiverThread('unused')
        decision = DecisionManager(imu=imu)
        await decision.say('Vật cản phía trước', urgent=True)
        await decision.instruction({'gps_valid':True, 'action':'turn_right',
          'target_bearing':90, 'stm32_heading_valid':True, 'valid_for_ms':3000,
          'route_id':'r','step_index':1,'distance_m':10,'text':'Rẽ phải'})
        self.assertFalse(decision.turn_state['turn_confirmed'])
        self.assertEqual(decision.last_output, 'Vật cản phía trước')
