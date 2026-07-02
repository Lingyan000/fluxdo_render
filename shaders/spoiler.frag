#include <flutter/runtime_effect.glsl>

// Spoiler 粒子尘埃场 —— 参考 Telegram 新版做法:粒子完全在 shader 里按
// hash(cell, time) 程序化生成,CPU 每帧只更新 time uniform,开销与
// spoiler 数量 / 面积基本无关。
//
// 视觉对齐旧 CPU 粒子系统:细小圆点(直径 ~1.2-1.4 逻辑px)、
// 3 档透明度、缓慢漂移 + 生灭闪烁。

uniform float u_time;  // 动画时间(秒)
uniform float u_seed;  // 每实例随机相位,避免多个 spoiler 同步闪烁
uniform vec4 u_color;  // 粒子基色(非预乘)

out vec4 fragColor;

// 粒子网格尺寸(逻辑 px):每 cell 一个粒子,密度 ≈ 1/(CELL²)
const float CELL = 3.5;

// hash(Dave Hoskins 风格,无 sin,移动 GPU 上精度稳定)
vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.zyx + 31.32);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 base = floor(p / CELL);
  float acc = 0.0;
  // 采样自身 + 8 邻域 cell:粒子出生点在自己 cell 内、漂移最多 ±CELL,
  // 3x3 邻域必然覆盖所有可能影响本像素的粒子。
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 cell = base + vec2(float(dx), float(dy));
      vec2 rc = hash22(cell + u_seed);
      // 生命周期 0.6~1.5s,相位随机 → 各粒子生灭错开
      float period = mix(0.6, 1.5, rc.x);
      float ft = u_time / period + rc.y * 17.0;
      float cycle = floor(ft);
      float t = fract(ft);
      // 每个周期重新随机:出生点(cell 内)/ 漂移方向 / 透明度档位
      vec2 rp = hash22(cell + u_seed + cycle * 0.9137);
      vec2 rd = hash22(cell * 1.3719 + u_seed + cycle * 0.5173);
      vec2 pos = (cell + rp) * CELL + (rd - 0.5) * 2.0 * CELL * t;
      // 淡入淡出包络
      float env = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, t));
      // 3 档透明度 0.3 / 0.65 / 1.0(对齐旧 CPU 粒子的 alphaType 分档)
      float tier = 0.3 + 0.35 * floor(hash12(cell * 2.17 + u_seed + cycle) * 3.0);
      // 圆点(半径 ~0.65 逻辑px,软边)
      float d = length(p - pos);
      acc += (1.0 - smoothstep(0.35, 0.95, d)) * tier * env;
    }
  }
  float a = min(acc, 1.0) * u_color.a;
  fragColor = vec4(u_color.rgb * a, a);
}
