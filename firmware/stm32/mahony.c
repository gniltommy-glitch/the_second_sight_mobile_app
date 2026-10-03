#include "mahony.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
static bool unit(float v[3]) {
    float n = sqrtf(v[0]*v[0]+v[1]*v[1]+v[2]*v[2]);
    if (!isfinite(n) || n < 1e-6f) return false;
    for (int i=0;i<3;i++) v[i]/=n;
    return true;
}
static void cross(const float a[3], const float b[3], float out[3]) {
    out[0]=a[1]*b[2]-a[2]*b[1]; out[1]=a[2]*b[0]-a[0]*b[2]; out[2]=a[0]*b[1]-a[1]*b[0];
}
void mahony_init(Mahony *s) {
    memset(s,0,sizeof(*s)); s->q[0]=1; s->kp=2.0f; s->ki=0.02f;
}
bool mahony_update(Mahony *s, const float gyro[3], const float a[3], const float m[3], float dt) {
    if (!isfinite(dt) || dt<=0 || dt>0.1f) return false;
    for (int i=0;i<3;i++) if (!isfinite(gyro[i])) return false;
    float gravity[3]={a[0],a[1],a[2]}, north[3]={m[0],m[1],m[2]};
    if (!unit(gravity) || !unit(north)) return false;
    float dot=0; for(int i=0;i<3;i++) dot+=gravity[i]*north[i];
    for(int i=0;i<3;i++) north[i]-=dot*gravity[i];
    if (!unit(north)) return false;
    const float w=s->q[0], x=s->q[1], y=s->q[2], z=s->q[3];
    float expected_g[3]={2*(x*z-w*y),2*(y*z+w*x),1-2*(x*x+y*y)};
    float expected_n[3]={1-2*(y*y+z*z),2*(x*y-w*z),2*(x*z+w*y)};
    float eg[3],en[3],g[3]; cross(gravity,expected_g,eg); cross(north,expected_n,en);
    for(int i=0;i<3;i++) {
        float error=eg[i]+en[i];
        s->integral[i]=fmaxf(-.2f,fminf(.2f,s->integral[i]+s->ki*error*dt));
        g[i]=gyro[i]+s->kp*error+s->integral[i];
    }
    s->q[0]+=(-x*g[0]-y*g[1]-z*g[2])*dt*.5f;
    s->q[1]+=(w*g[0]+y*g[2]-z*g[1])*dt*.5f;
    s->q[2]+=(w*g[1]-x*g[2]+z*g[0])*dt*.5f;
    s->q[3]+=(w*g[2]+x*g[1]-y*g[0])*dt*.5f;
    float norm=0; for(int i=0;i<4;i++) norm+=s->q[i]*s->q[i]; norm=sqrtf(norm);
    if (!isfinite(norm) || norm<1e-6f) { mahony_init(s); return false; }
    for(int i=0;i<4;i++) s->q[i]/=norm;
    return true;
}
int imu_packet(char *out, size_t size, const Mahony *s, uint32_t seq,
               uint32_t timestamp_ms, bool calibrated, float yaw_offset_degrees) {
    if (!isfinite(yaw_offset_degrees)) return -1;
    const float rad=0.017453292519943295f;
    const float c=cosf(yaw_offset_degrees*rad*.5f), t=sinf(yaw_offset_degrees*rad*.5f);
    float w=c*s->q[0]-t*s->q[3], x=c*s->q[1]-t*s->q[2];
    float y=c*s->q[2]+t*s->q[1], z=c*s->q[3]+t*s->q[0];
    float heading=fmodf(atan2f(2*(w*z+x*y),1-2*(y*y+z*z))/rad+360,360);
    float pitch=asinf(fmaxf(-1,fminf(1,2*(w*y-z*x))))/rad;
    float roll=atan2f(2*(w*x+y*z),1-2*(x*x+y*y))/rad;
    int n=snprintf(out,size,"{\"type\":\"imu\",\"version\":1,\"sequence\":%lu,\"timestamp_ms\":%lu,\"calibrated\":%s,\"quaternion\":[%.6f,%.6f,%.6f,%.6f],\"heading\":%.3f,\"pitch\":%.3f,\"roll\":%.3f}\n",
        (unsigned long)seq,(unsigned long)timestamp_ms,calibrated?"true":"false",w,x,y,z,heading,pitch,roll);
    return n>=0 && (size_t)n<size ? n : -1;
}
