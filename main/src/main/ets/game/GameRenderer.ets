/**
 * GameRenderer.ets — ArkTS 侧的帧缓冲构造器。
 *
 * 棋盘不交给 ArkUI：每帧把「归一化矩形 + 颜色 + 圆角 + 高光」写进 Float32Array，
 * 由 libgame.so 直接画到 XComponent 的 Surface 上。
 * 因此 uitest dumpLayout 只能看到一个 XComponent 节点，看不到 64 个格子。
 */

import nativeGame from 'libgame.so';

/** 单帧最多容纳的矩形数（棋盘 64 格 + 底板 + 槽位 + 选中态，留足余量）。 */
export const MAX_RECTS: number = 320;

/** 一块可复用的帧缓冲：避免每帧重新分配大数组造成 GC 抖动。 */
export class FrameBuffer {
  private data: Float32Array;
  private count: number = 0;

  constructor(capacity: number = MAX_RECTS) {
    this.data = new Float32Array(2 + capacity * 10);
  }

  public reset(): void {
    this.count = 0;
  }

  /**
   * 追加一个圆角矩形。
   * @param x 左上角 x（相对 Surface 宽度，0..1）
   * @param y 左上角 y（相对 Surface 高度，0..1，向下为正）
   * @param radius 圆角半径，相对短边的比例（0..0.5）
   * @param glow 高光强度（0..1）
   */
  public addRect(x: number, y: number, w: number, h: number,
    r: number, g: number, b: number, a: number,
    radius: number, glow: number): void {
    if (this.count * 10 + 12 > this.data.length) {
      return;
    }
    const offset: number = 2 + this.count * 10;
    this.data[offset] = x;
    this.data[offset + 1] = y;
    this.data[offset + 2] = w;
    this.data[offset + 3] = h;
    this.data[offset + 4] = r;
    this.data[offset + 5] = g;
    this.data[offset + 6] = b;
    this.data[offset + 7] = a;
    this.data[offset + 8] = radius;
    this.data[offset + 9] = glow;
    this.count++;
  }

  /** 提交到 native 绘制（Surface 未就绪时 native 会缓存，就绪后补画）。 */
  public flush(): void {
    this.data[0] = this.count;
    this.data[1] = 0;
    nativeGame.setFrame(this.data);
  }

  public size(): number {
    return this.count;
  }
}
