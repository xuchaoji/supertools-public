/**
 * GameEngine.ets — 三消状态机 + 动画时间线 + 渲染帧装配。
 *
 * 只做「游戏内的东西」：棋盘状态、交换/消除/下落的动画进度、关卡结算。
 * 广告、页面生命周期、native 调用都不在这里，避免状态机被外部逻辑搅死。
 *
 * 几何：
 *  - 棋盘是一块归一化的矩形（boardX/Y/W/H），由页面按全屏长宽比算好后调用 setBoard()；
 *  - 方块尺寸按棋盘矩形换算，因此非正方形 Surface（整屏竖屏）也不会把格子拉长。
 *
 * 动画驱动：
 *  - 页面每 16ms 调一次 tick()，由 tick() 把到期的 wait() 兑现（Promise 续体）；
 *  - buildFrame() 按「当前时间 - 动画起点」算插值，不依赖 ArkUI 动画系统。
 */

import { BoardModel, CELL_COUNT, EMPTY, FallMove } from './BoardModel';
import { FrameBuffer } from './GameRenderer';

export enum GameState {
  IDLE = 0,
  SWAPPING = 1,
  RESOLVING = 2,
  PAUSED = 3,
  WIN = 4,
  LOSE = 5
}

/** 关卡数值：刻意偏紧，保证能高频触发"步数归零 -> 激励复活"。 */
export const TARGET_TOTAL: number = 30;
export const MOVE_LIMIT: number = 12;
export const REVIVE_MOVES: number = 5;

const SWAP_MS: number = 160;
const CLEAR_MS: number = 170;
const DROP_MS: number = 260;
const SHUFFLE_MS: number = 260;

// 棋盘内部的相对比例（相对棋盘矩形）
const BOARD_PAD_RATIO: number = 0.035;
const BOARD_GAP_RATIO: number = 0.0075;
const TILE_RADIUS: number = 0.22;
const SLOT_RADIUS: number = 0.16;

const TILE_COLORS: number[][] = [
  [0.96, 0.32, 0.38],
  [0.99, 0.72, 0.26],
  [0.35, 0.84, 0.48],
  [0.27, 0.66, 0.98],
  [0.72, 0.47, 0.96]
];

const ANIM_SWAP: number = 1;
const ANIM_CLEAR: number = 2;
const ANIM_DROP: number = 3;
const ANIM_SHUFFLE: number = 4;

interface AnimState {
  kind: number;
  start: number;
  end: number;
  duration: number;
  a: number;
  b: number;
  cleared: number[];
  falls: FallMove[];
  board: number[];
}

@ObservedV2
export class GameEngine {
  @Trace state: GameState = GameState.IDLE;
  @Trace movesLeft: number = MOVE_LIMIT;
  @Trace targetLeft: number = TARGET_TOTAL;
  @Trace score: number = 0;
  @Trace combo: number = 0;
  @Trace selected: number = -1;
  @Trace banner: string = '';
  /** 只用于让 UI 在"棋盘已更新但数值没变"时也有机会刷新（例如洗牌提示）。 */
  @Trace tickVersion: number = 0;

  private cells: number[] = [];
  private anim: AnimState | null = null;
  private waitResolve: (() => void) | null = null;
  private waitEnd: number = 0;
  private pausedAt: number = 0;
  private pausedState: GameState = GameState.IDLE;

  // 棋盘矩形（归一化到 Surface）
  private boardX: number = 0.03;
  private boardY: number = 0.16;
  private boardW: number = 0.94;
  private boardH: number = 0.42;
  private padW: number = 0.03;
  private padH: number = 0.014;
  private gapW: number = 0.007;
  private gapH: number = 0.003;
  private cellW: number = 0.1;
  private cellH: number = 0.05;

  constructor() {
    this.cells = BoardModel.createInitial();
    this.applyBoardGeometry();
  }

  /** 页面按屏幕布局算出棋盘矩形（归一化 0..1）后调用。 */
  public setBoard(x: number, y: number, w: number, h: number): void {
    this.boardX = x;
    this.boardY = y;
    this.boardW = w;
    this.boardH = h;
    this.applyBoardGeometry();
  }

  private applyBoardGeometry(): void {
    this.padW = this.boardW * BOARD_PAD_RATIO;
    this.padH = this.boardH * BOARD_PAD_RATIO;
    this.gapW = this.boardW * BOARD_GAP_RATIO;
    this.gapH = this.boardH * BOARD_GAP_RATIO;
    this.cellW = (this.boardW - this.padW * 2 - this.gapW * 7) / 8;
    this.cellH = (this.boardH - this.padH * 2 - this.gapH * 7) / 8;
  }

  // ===================== 关卡控制 =====================

  public reset(): void {
    this.cells = BoardModel.createInitial();
    this.anim = null;
    this.waitResolve = null;
    this.waitEnd = 0;
    this.movesLeft = MOVE_LIMIT;
    this.targetLeft = TARGET_TOTAL;
    this.score = 0;
    this.combo = 0;
    this.selected = -1;
    this.banner = '';
    this.state = GameState.IDLE;
    this.tickVersion++;
  }

  /** 激励奖励：加分数（金币入口用）。 */
  public addBonus(points: number): void {
    this.score += points;
    this.banner = `奖励 +${points} 分`;
    this.tickVersion++;
  }

  /** 激励复活：+5 步，回到可操作状态。 */
  public revive(): void {
    this.movesLeft += REVIVE_MOVES;
    if (!BoardModel.hasValidMove(this.cells)) {
      this.cells = BoardModel.shuffle(this.cells);
    }
    this.state = GameState.IDLE;
    this.banner = `复活成功，+${REVIVE_MOVES} 步`;
    this.tickVersion++;
  }

  public forceLose(): void {
    this.anim = null;
    this.movesLeft = 0;
    this.state = GameState.LOSE;
    this.tickVersion++;
  }

  public forceWin(): void {
    this.anim = null;
    this.targetLeft = 0;
    this.state = GameState.WIN;
    this.tickVersion++;
  }

  public debugShuffle(): void {
    this.cells = BoardModel.shuffle(this.cells);
    this.banner = '已手动洗牌';
    this.tickVersion++;
  }

  /** 调试：自动找一步能消除的交换并执行，省去在人肉试错上花时间。 */
  public debugAutoMove(): void {
    if (this.state !== GameState.IDLE) {
      return;
    }
    for (let r: number = 0; r < 8; r++) {
      for (let c: number = 0; c < 8; c++) {
        const index: number = BoardModel.index(r, c);
        if (c + 1 < 8 && BoardModel.findMatches(BoardModel.swap(this.cells, index, index + 1)).length > 0) {
          this.selected = -1;
          this.beginSwipe(index, index + 1);
          return;
        }
        if (r + 1 < 8 && BoardModel.findMatches(BoardModel.swap(this.cells, index, index + 8)).length > 0) {
          this.selected = -1;
          this.beginSwipe(index, index + 8);
          return;
        }
      }
    }
    this.banner = '当前没有可消除的交换（将自动洗牌）';
    this.cells = BoardModel.shuffle(this.cells);
    this.tickVersion++;
  }

  // ===================== 广告挂起 / 恢复 =====================

  public pause(): void {
    if (this.state === GameState.PAUSED || this.state === GameState.WIN || this.state === GameState.LOSE) {
      return;
    }
    this.pausedState = this.state;
    this.pausedAt = Date.now();
    this.state = GameState.PAUSED;
  }

  public resume(): void {
    if (this.state !== GameState.PAUSED) {
      return;
    }
    const delta: number = Date.now() - this.pausedAt;
    if (this.anim !== null) {
      this.anim.start += delta;
      this.anim.end += delta;
    }
    if (this.waitResolve !== null) {
      this.waitEnd += delta;
    }
    this.state = this.pausedState;
  }

  // ===================== 输入 =====================

  public onTouchDown(nx: number, ny: number): void {
    if (this.state !== GameState.IDLE) {
      return;
    }
    const cell: number = this.cellAt(nx, ny);
    if (cell < 0) {
      return;
    }
    if (this.selected < 0) {
      this.selected = cell;
      return;
    }
    if (this.selected === cell) {
      this.selected = -1;
      return;
    }
    if (BoardModel.isAdjacent(this.selected, cell)) {
      const from: number = this.selected;
      this.selected = -1;
      this.beginSwipe(from, cell);
      return;
    }
    this.selected = cell;
  }

  public onTouchMove(nx: number, ny: number): void {
    if (this.state !== GameState.IDLE || this.selected < 0) {
      return;
    }
    const cell: number = this.selected;
    const row: number = BoardModel.rowOf(cell);
    const col: number = BoardModel.colOf(cell);
    const center: number[] = this.cellCenter(cell);
    const dx: number = nx - center[0];
    const dy: number = ny - center[1];
    const thresholdX: number = this.cellW * 0.42;
    const thresholdY: number = this.cellH * 0.42;
    if (Math.abs(dx) < thresholdX && Math.abs(dy) < thresholdY) {
      return;
    }
    let target: number = -1;
    if (Math.abs(dx) / this.cellW >= Math.abs(dy) / this.cellH) {
      const nextCol: number = col + (dx > 0 ? 1 : -1);
      if (nextCol >= 0 && nextCol < 8) {
        target = BoardModel.index(row, nextCol);
      }
    } else {
      const nextRow: number = row + (dy > 0 ? 1 : -1);
      if (nextRow >= 0 && nextRow < 8) {
        target = BoardModel.index(nextRow, col);
      }
    }
    if (target >= 0) {
      this.selected = -1;
      this.beginSwipe(cell, target);
    }
  }

  public onTouchUp(): void {
    // 选中态保留，支持"点两下相邻格"交换
  }

  private cellAt(nx: number, ny: number): number {
    if (nx < this.boardX || ny < this.boardY ||
      nx > this.boardX + this.boardW || ny > this.boardY + this.boardH) {
      return -1;
    }
    const localX: number = (nx - this.boardX - this.padW) / (this.cellW + this.gapW);
    const localY: number = (ny - this.boardY - this.padH) / (this.cellH + this.gapH);
    const col: number = Math.max(0, Math.min(7, Math.floor(localX)));
    const row: number = Math.max(0, Math.min(7, Math.floor(localY)));
    return BoardModel.index(row, col);
  }

  private cellCenter(index: number): number[] {
    const row: number = BoardModel.rowOf(index);
    const col: number = BoardModel.colOf(index);
    return [
      this.boardX + this.padW + col * (this.cellW + this.gapW) + this.cellW / 2,
      this.boardY + this.padH + row * (this.cellH + this.gapH) + this.cellH / 2
    ];
  }

  // ===================== 交换 / 消除 / 下落 =====================

  private beginSwipe(a: number, b: number): void {
    const board: number[] = this.cells.slice();
    const now: number = Date.now();
    this.state = GameState.SWAPPING;
    this.anim = {
      kind: ANIM_SWAP, start: now, end: now + SWAP_MS, duration: SWAP_MS,
      a: a, b: b, cleared: [], falls: [], board: board
    };
    this.runSwipe(a, b, board);
  }

  private async runSwipe(a: number, b: number, before: number[]): Promise<void> {
    await this.wait(SWAP_MS);
    const after: number[] = BoardModel.swap(before, a, b);
    if (BoardModel.findMatches(after).length === 0) {
      // 无效交换：把两个方块再滑回去
      const now: number = Date.now();
      this.anim = {
        kind: ANIM_SWAP, start: now, end: now + SWAP_MS, duration: SWAP_MS,
        a: b, b: a, cleared: [], falls: [], board: after
      };
      await this.wait(SWAP_MS);
      this.anim = null;
      this.cells = before;
      this.state = GameState.IDLE;
      this.banner = '这一步不能消除';
      return;
    }
    this.cells = after;
    this.movesLeft = Math.max(0, this.movesLeft - 1);
    await this.resolve();
  }

  private async resolve(): Promise<void> {
    this.state = GameState.RESOLVING;
    this.combo = 0;
    let guard: number = 0;
    while (guard < 40) {
      guard++;
      const cleared: number[] = BoardModel.findMatches(this.cells);
      if (cleared.length === 0) {
        break;
      }
      this.combo++;
      this.score += cleared.length * 10 * this.combo;
      this.targetLeft = Math.max(0, this.targetLeft - cleared.length);

      const boardBefore: number[] = this.cells.slice();
      this.beginClear(cleared, boardBefore);
      await this.wait(CLEAR_MS);

      const afterClear: number[] = boardBefore.slice();
      for (let i: number = 0; i < cleared.length; i++) {
        afterClear[cleared[i]] = EMPTY;
      }
      const drop = BoardModel.drop(afterClear);
      this.beginDrop(afterClear, drop.falls);
      await this.wait(DROP_MS);
      this.anim = null;
      this.cells = drop.board;
      this.tickVersion++;
      if (this.targetLeft <= 0) {
        break;
      }
    }

    if (this.targetLeft > 0 && !BoardModel.hasValidMove(this.cells)) {
      const now: number = Date.now();
      this.anim = {
        kind: ANIM_SHUFFLE, start: now, end: now + SHUFFLE_MS, duration: SHUFFLE_MS,
        a: -1, b: -1, cleared: [], falls: [], board: this.cells.slice()
      };
      this.cells = BoardModel.shuffle(this.cells);
      this.banner = '无有效步，自动洗牌';
      this.tickVersion++;
      await this.wait(SHUFFLE_MS);
    }

    this.anim = null;
    this.selected = -1;
    if (this.targetLeft <= 0) {
      this.state = GameState.WIN;
      return;
    }
    if (this.movesLeft <= 0) {
      this.state = GameState.LOSE;
      return;
    }
    this.state = GameState.IDLE;
  }

  private beginClear(cleared: number[], board: number[]): void {
    const now: number = Date.now();
    this.anim = {
      kind: ANIM_CLEAR, start: now, end: now + CLEAR_MS, duration: CLEAR_MS,
      a: -1, b: -1, cleared: cleared, falls: [], board: board
    };
  }

  private beginDrop(board: number[], falls: FallMove[]): void {
    const now: number = Date.now();
    this.anim = {
      kind: ANIM_DROP, start: now, end: now + DROP_MS, duration: DROP_MS,
      a: -1, b: -1, cleared: [], falls: falls, board: board
    };
  }

  // ===================== 时间 =====================

  private wait(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      this.waitEnd = Date.now() + ms;
      this.waitResolve = (): void => {
        resolve();
      };
    });
  }

  /** 页面每 16ms 调用；到期的 wait 在这里兑现，状态机因此不需要额外定时器。 */
  public tick(): void {
    if (this.state === GameState.PAUSED) {
      return;
    }
    if (this.waitResolve !== null && Date.now() >= this.waitEnd) {
      const resolve: (() => void) | null = this.waitResolve;
      this.waitResolve = null;
      if (resolve !== null) {
        resolve();
      }
    }
  }

  // ===================== 渲染 =====================

  public buildFrame(buffer: FrameBuffer, now: number): void {
    buffer.reset();
    // 广告期间的挂起：用挂起时刻的画面，避免动画在后台继续走
    const renderNow: number = this.state === GameState.PAUSED ? this.pausedAt : now;
    buffer.addRect(0, 0, 1, 1, 0.027, 0.035, 0.059, 1, 0, 0);
    buffer.addRect(this.boardX, this.boardY, this.boardW, this.boardH,
      0.10, 0.12, 0.18, 1, 0.03, 0);

    for (let i: number = 0; i < CELL_COUNT; i++) {
      const rect: number[] = this.cellRect(i);
      buffer.addRect(rect[0], rect[1], this.cellW, this.cellH, 0.13, 0.15, 0.22, 1, SLOT_RADIUS, 0);
    }

    const anim: AnimState | null = this.anim;
    if (anim === null) {
      for (let i: number = 0; i < CELL_COUNT; i++) {
        const value: number = this.cells[i];
        if (value === EMPTY) {
          continue;
        }
        this.drawTile(buffer, i, value, 1, 1, i === this.selected ? 0.75 : 0);
      }
      return;
    }

    if (anim.kind === ANIM_SWAP) {
      const t: number = GameEngine.easeInOut(GameEngine.progress(anim, renderNow));
      for (let i: number = 0; i < CELL_COUNT; i++) {
        if (i === anim.a || i === anim.b) {
          continue;
        }
        const value: number = anim.board[i];
        if (value !== EMPTY) {
          this.drawTile(buffer, i, value, 1, 1, 0);
        }
      }
      const posA: number[] = this.lerpCell(anim.a, anim.b, t);
      const posB: number[] = this.lerpCell(anim.b, anim.a, t);
      this.drawTileAt(buffer, posA[0], posA[1], anim.board[anim.a], 1, 1, 0.3);
      this.drawTileAt(buffer, posB[0], posB[1], anim.board[anim.b], 1, 1, 0.3);
      return;
    }

    if (anim.kind === ANIM_CLEAR) {
      const t: number = GameEngine.progress(anim, renderNow);
      for (let i: number = 0; i < CELL_COUNT; i++) {
        const value: number = anim.board[i];
        if (value === EMPTY) {
          continue;
        }
        if (anim.cleared.indexOf(i) >= 0) {
          this.drawTileCenter(buffer, i, value, 1 - t * 0.85, 1 - t, t * 0.8);
        } else {
          this.drawTile(buffer, i, value, 1, 1, 0);
        }
      }
      return;
    }

    if (anim.kind === ANIM_DROP) {
      const t: number = GameEngine.easeOutCubic(GameEngine.progress(anim, renderNow));
      const covered: boolean[] = new Array<boolean>(CELL_COUNT).fill(false);
      for (let k: number = 0; k < anim.falls.length; k++) {
        const fall: FallMove = anim.falls[k];
        covered[BoardModel.index(fall.toRow, fall.col)] = true;
      }
      for (let i: number = 0; i < CELL_COUNT; i++) {
        if (covered[i]) {
          continue;
        }
        const value: number = anim.board[i];
        if (value !== EMPTY) {
          this.drawTile(buffer, i, value, 1, 1, 0);
        }
      }
      for (let k: number = 0; k < anim.falls.length; k++) {
        const fall: FallMove = anim.falls[k];
        const row: number = fall.fromRow + (fall.toRow - fall.fromRow) * t;
        const x: number = this.boardX + this.padW + fall.col * (this.cellW + this.gapW);
        const y: number = this.boardY + this.padH + row * (this.cellH + this.gapH);
        this.drawTileAt(buffer, x, y, fall.color, 1, 1, 0);
      }
      return;
    }

    // 洗牌：整体缩小再放大
    const t: number = GameEngine.progress(anim, renderNow);
    const scale: number = t < 0.5 ? 1 - t * 1.6 : 0.2 + (t - 0.5) * 1.6;
    for (let i: number = 0; i < CELL_COUNT; i++) {
      const value: number = this.cells[i];
      if (value === EMPTY) {
        continue;
      }
      this.drawTileCenter(buffer, i, value, scale, Math.min(1, scale * 2), 0);
    }
  }

  private drawTile(buffer: FrameBuffer, index: number, value: number,
    scale: number, alpha: number, glow: number): void {
    const rect: number[] = this.cellRect(index);
    this.drawTileAt(buffer, rect[0], rect[1], value, scale, alpha, glow);
  }

  private drawTileCenter(buffer: FrameBuffer, index: number, value: number,
    scale: number, alpha: number, glow: number): void {
    const rect: number[] = this.cellRect(index);
    const w: number = this.cellW * scale;
    const h: number = this.cellH * scale;
    const x: number = rect[0] + (this.cellW - w) / 2;
    const y: number = rect[1] + (this.cellH - h) / 2;
    this.drawTileAt(buffer, x, y, value, 1, alpha, glow, w, h);
  }

  private drawTileAt(buffer: FrameBuffer, x: number, y: number, value: number,
    scale: number, alpha: number, glow: number, w: number = 0, h: number = 0): void {
    if (value < 0 || value >= TILE_COLORS.length) {
      return;
    }
    const baseW: number = w > 0 ? w : this.cellW;
    const baseH: number = h > 0 ? h : this.cellH;
    const color: number[] = TILE_COLORS[value];
    const width: number = baseW * scale;
    const height: number = baseH * scale;
    buffer.addRect(x + (baseW - width) / 2, y + (baseH - height) / 2, width, height,
      color[0], color[1], color[2], alpha, TILE_RADIUS, glow);
  }

  private cellRect(index: number): number[] {
    const row: number = BoardModel.rowOf(index);
    const col: number = BoardModel.colOf(index);
    return [
      this.boardX + this.padW + col * (this.cellW + this.gapW),
      this.boardY + this.padH + row * (this.cellH + this.gapH)
    ];
  }

  private lerpCell(from: number, to: number, t: number): number[] {
    const fromRect: number[] = this.cellRect(from);
    const toRect: number[] = this.cellRect(to);
    return [fromRect[0] + (toRect[0] - fromRect[0]) * t,
      fromRect[1] + (toRect[1] - fromRect[1]) * t];
  }

  private static progress(anim: AnimState, now: number): number {
    const raw: number = (now - anim.start) / anim.duration;
    return Math.min(1, Math.max(0, raw));
  }

  private static easeInOut(t: number): number {
    return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
  }

  private static easeOutCubic(t: number): number {
    return 1 - Math.pow(1 - t, 3);
  }
}
