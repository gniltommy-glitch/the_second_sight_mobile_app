#include "mahony.h"
#include <assert.h>
#include <math.h>
#include <string.h>
int main(void) {
    Mahony s; mahony_init(&s);
    float g[3]={0,0,0}, a[3]={0,0,1}, m[3]={1,0,0};
    for(int i=0;i<1000;i++) assert(mahony_update(&s,g,a,m,.01f));
    assert(fabsf(s.q[0]-1)<.001f);
    float bad[3]={NAN,0,0}; assert(!mahony_update(&s,bad,a,m,.01f));
    char out[512];
    assert(imu_packet(out,sizeof(out),&s,1,50,true,90)>0);
    assert(strstr(out,"\"heading\":90.000"));
    assert(imu_packet(out,8,&s,1,50,true,0)==-1);
    // Converge on 90 degree east from horizontal magnetic north in body -y.
    m[0]=0; m[1]=-1;
    for(int i=0;i<5000;i++) assert(mahony_update(&s,g,a,m,.01f));
    assert(fabsf(s.q[0]-.70710678f)<.01f && fabsf(s.q[3]-.70710678f)<.01f);
    return 0;
}
