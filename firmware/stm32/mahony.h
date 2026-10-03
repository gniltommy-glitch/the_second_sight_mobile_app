#ifndef SECONDSIGHT_MAHONY_H
#define SECONDSIGHT_MAHONY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef struct { float q[4], integral[3], kp, ki; } Mahony;
void mahony_init(Mahony *s);
/* Inputs: gyro rad/s, acceleration & magnetic field calibrated in same axes.
   Reference: x north, y east, z down; a is the measured gravity direction.
   Returns false on invalid samples; never infer calibration from this result. */
bool mahony_update(Mahony *s, const float gyro[3], const float a[3], const float m[3], float dt);
/* Apply declination/mount yaw before output; set calibrated only after measured
   gyro bias, accel/mag calibration, mounting transform and convergence checks. */
int imu_packet(char *out, size_t size, const Mahony *s, uint32_t seq,
               uint32_t timestamp_ms, bool calibrated, float yaw_offset_degrees);
#endif
