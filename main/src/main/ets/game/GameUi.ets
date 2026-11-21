/**
 * GameUi.ets — 原生 UI 层的显示列表。
 *
 * 页面不创建任何 ArkUI 控件：HUD、按钮、弹窗、调试面板都通过这里描述成
 * 「归一化矩形 + 文本」，交给 libgame.so 用 OH_Drawing 离屏画成一张透明纹理，
 * 再叠加到棋盘上。布局树里因此只剩一个 XComponent。
 */

import nativeGame from 'libgame.so';

/** 文本对齐。 */
export const UI_LEFT: number = 0;
export const UI_CENTER: number = 1;
export const UI_RIGHT: number = 2;

const FLOATS_PER_RECT: number = 10;

export class UiRectBuffer {
  private data: Float32Array;
  private count: number = 0;

  constructor(capacity: number = 320) {
    this.data = new Float32Array(2 + capacity * FLOATS_PER_RECT);
  }

  public reset(): void {
    this.count = 0;
  }

  /** 坐标归一化 0..1；radius 为矩形短边的比例（0..0.5）。 */
  public add(x: number, y: number, w: number, h: number,
    r: number, g: number, b: number, a: number, radius: number): void {
    if (this.count * FLOATS_PER_RECT + 12 > this.data.length) {
      return;
    }
    const o: number = 2 + this.count * FLOATS_PER_RECT;
    this.data[o] = x;
    this.data[o + 1] = y;
    this.data[o + 2] = w;
    this.data[o + 3] = h;
    this.data[o + 4] = r;
    this.data[o + 5] = g;
    this.data[o + 6] = b;
    this.data[o + 7] = a;
    this.data[o + 8] = radius;
    this.data[o + 9] = 0;
    this.count++;
  }

  public flush(): void {
    this.data[0] = this.count;
    this.data[1] = 0;
    nativeGame.setUiRects(this.data);
  }
}

export class UiTextBuffer {
  private texts: string[] = [];
  private params: number[] = [];

  public reset(): void {
    this.texts = [];
    this.params = [];
  }

  /**
   * @param x 归一化锚点 x
   * @param y 归一化文本顶部 y
   * @param size 字号（相对 Surface 高度的比例）
   * @param align UI_LEFT / UI_CENTER / UI_RIGHT
   */
  public add(text: string, x: number, y: number, size: number,
    r: number, g: number, b: number, a: number, align: number, bold: boolean): void {
    this.texts.push(text);
    this.params.push(x, y, size, r, g, b, a, align, bold ? 1 : 0);
  }

  public flush(): void {
    nativeGame.setUiTexts(this.texts, new Float32Array(this.params));
  }
}
