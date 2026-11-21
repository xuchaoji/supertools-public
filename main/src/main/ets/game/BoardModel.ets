/**
 * BoardModel.ets — 三消纯逻辑层（不依赖 ArkUI / native，便于单独推理与回归）。
 *
 * 规则：
 *  - 8×8 棋盘、5 种元素（0..4），EMPTY = -1 表示空位；
 *  - 初始棋盘无三连，且至少存在一步有效交换；
 *  - 匹配为横/纵 3 连及以上；
 *  - 消除后整列下落、顶部补齐；无有效步时自动洗牌。
 */

export const BOARD_SIZE: number = 8;
export const CELL_COUNT: number = BOARD_SIZE * BOARD_SIZE;
export const COLOR_COUNT: number = 5;
export const EMPTY: number = -1;

/** 下落描述：col 列的元素从 fromRow 落到 toRow（fromRow 可为负数 = 新元素从顶部进入）。 */
export interface FallMove {
  col: number;
  fromRow: number;
  toRow: number;
  color: number;
}

export interface DropResult {
  board: number[];
  falls: FallMove[];
}

export class BoardModel {
  public static index(row: number, col: number): number {
    return row * BOARD_SIZE + col;
  }

  public static rowOf(index: number): number {
    return Math.floor(index / BOARD_SIZE);
  }

  public static colOf(index: number): number {
    return index % BOARD_SIZE;
  }

  public static randomColor(): number {
    return Math.floor(Math.random() * COLOR_COUNT);
  }

  /** 两个下标是否四邻接（上下左右）。 */
  public static isAdjacent(a: number, b: number): boolean {
    const dr: number = Math.abs(BoardModel.rowOf(a) - BoardModel.rowOf(b));
    const dc: number = Math.abs(BoardModel.colOf(a) - BoardModel.colOf(b));
    return dr + dc === 1;
  }

  /**
   * 生成初始棋盘：逐格随机时避开"左侧两格相同"与"上方两格相同"，
   * 因此天然没有三连；再校验至少一步可消除。
   */
  public static createInitial(): number[] {
    for (let attempt: number = 0; attempt < 80; attempt++) {
      const board: number[] = new Array<number>(CELL_COUNT).fill(EMPTY);
      for (let r: number = 0; r < BOARD_SIZE; r++) {
        for (let c: number = 0; c < BOARD_SIZE; c++) {
          board[BoardModel.index(r, c)] = BoardModel.safeColor(board, r, c);
        }
      }
      if (BoardModel.hasValidMove(board)) {
        return board;
      }
    }
    // 极端情况下的兜底：顺序填充（仍保证无三连）
    const board: number[] = new Array<number>(CELL_COUNT).fill(EMPTY);
    for (let r: number = 0; r < BOARD_SIZE; r++) {
      for (let c: number = 0; c < BOARD_SIZE; c++) {
        board[BoardModel.index(r, c)] = (r + c) % COLOR_COUNT;
      }
    }
    return board;
  }

  private static safeColor(board: number[], row: number, col: number): number {
    const left1: number = col >= 1 ? board[BoardModel.index(row, col - 1)] : -2;
    const left2: number = col >= 2 ? board[BoardModel.index(row, col - 2)] : -2;
    const up1: number = row >= 1 ? board[BoardModel.index(row - 1, col)] : -2;
    const up2: number = row >= 2 ? board[BoardModel.index(row - 2, col)] : -2;
    let color: number = BoardModel.randomColor();
    let guard: number = 0;
    while (((left1 === left2 && color === left1) || (up1 === up2 && color === up1)) && guard < 20) {
      color = BoardModel.randomColor();
      guard++;
    }
    return color;
  }

  /** 返回全部应消除的下标（横向/纵向 3 连及以上）。 */
  public static findMatches(board: number[]): number[] {
    const mark: boolean[] = new Array<boolean>(CELL_COUNT).fill(false);
    // 横向
    for (let r: number = 0; r < BOARD_SIZE; r++) {
      let c: number = 0;
      while (c < BOARD_SIZE) {
        const value: number = board[BoardModel.index(r, c)];
        let end: number = c + 1;
        while (end < BOARD_SIZE && board[BoardModel.index(r, end)] === value) {
          end++;
        }
        if (value !== EMPTY && end - c >= 3) {
          for (let k: number = c; k < end; k++) {
            mark[BoardModel.index(r, k)] = true;
          }
        }
        c = end;
      }
    }
    // 纵向
    for (let c: number = 0; c < BOARD_SIZE; c++) {
      let r: number = 0;
      while (r < BOARD_SIZE) {
        const value: number = board[BoardModel.index(r, c)];
        let end: number = r + 1;
        while (end < BOARD_SIZE && board[BoardModel.index(end, c)] === value) {
          end++;
        }
        if (value !== EMPTY && end - r >= 3) {
          for (let k: number = r; k < end; k++) {
            mark[BoardModel.index(k, c)] = true;
          }
        }
        r = end;
      }
    }
    const result: number[] = [];
    for (let i: number = 0; i < CELL_COUNT; i++) {
      if (mark[i]) {
        result.push(i);
      }
    }
    return result;
  }

  /** 是否存在任意一处可消除（用于有效步检测，含提前返回）。 */
  public static hasAnyMatch(board: number[]): boolean {
    for (let r: number = 0; r < BOARD_SIZE; r++) {
      for (let c: number = 0; c < BOARD_SIZE; c++) {
        const v: number = board[BoardModel.index(r, c)];
        if (v === EMPTY) {
          continue;
        }
        if (c + 2 < BOARD_SIZE &&
          board[BoardModel.index(r, c + 1)] === v &&
          board[BoardModel.index(r, c + 2)] === v) {
          return true;
        }
        if (r + 2 < BOARD_SIZE &&
          board[BoardModel.index(r + 1, c)] === v &&
          board[BoardModel.index(r + 2, c)] === v) {
          return true;
        }
      }
    }
    return false;
  }

  public static swap(board: number[], a: number, b: number): number[] {
    const next: number[] = board.slice();
    const tmp: number = next[a];
    next[a] = next[b];
    next[b] = tmp;
    return next;
  }

  /** 是否存在至少一步可消除的交换（枚举右邻/下邻）。 */
  public static hasValidMove(board: number[]): boolean {
    for (let r: number = 0; r < BOARD_SIZE; r++) {
      for (let c: number = 0; c < BOARD_SIZE; c++) {
        const index: number = BoardModel.index(r, c);
        if (c + 1 < BOARD_SIZE) {
          if (BoardModel.hasAnyMatch(BoardModel.swap(board, index, index + 1))) {
            return true;
          }
        }
        if (r + 1 < BOARD_SIZE) {
          if (BoardModel.hasAnyMatch(BoardModel.swap(board, index, index + BOARD_SIZE))) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /**
   * 消除后的重排：逐列把非空元素压到底部，顶部空位用新颜色补齐，
   * 同时产出每个元素的下落轨迹（供动画插值）。
   */
  public static drop(board: number[]): DropResult {
    const next: number[] = new Array<number>(CELL_COUNT).fill(EMPTY);
    const falls: FallMove[] = [];
    for (let c: number = 0; c < BOARD_SIZE; c++) {
      let writeRow: number = BOARD_SIZE - 1;
      for (let r: number = BOARD_SIZE - 1; r >= 0; r--) {
        const value: number = board[BoardModel.index(r, c)];
        if (value === EMPTY) {
          continue;
        }
        next[BoardModel.index(writeRow, c)] = value;
        if (writeRow !== r) {
          falls.push({ col: c, fromRow: r, toRow: writeRow, color: value });
        }
        writeRow--;
      }
      // 顶部补齐：新元素从棋盘上方（负数行）落下，
      // 越靠上的新元素起点越高，视觉上才是"从顶部补进来"
      let spawnIndex: number = 1;
      for (let r: number = writeRow; r >= 0; r--) {
        const color: number = BoardModel.randomColor();
        next[BoardModel.index(r, c)] = color;
        falls.push({ col: c, fromRow: r - writeRow - spawnIndex, toRow: r, color: color });
        spawnIndex++;
      }
    }
    return { board: next, falls: falls };
  }

  /** 死局洗牌：随机重排现有颜色，直到无三连且存在有效步。 */
  public static shuffle(board: number[]): number[] {
    const colors: number[] = board.filter((v: number) => v !== EMPTY);
    if (colors.length !== CELL_COUNT) {
      // 棋盘不完整时不洗牌，避免把空位洗成非空
      return board.slice();
    }
    for (let attempt: number = 0; attempt < 200; attempt++) {
      const pool: number[] = colors.slice();
      for (let i: number = pool.length - 1; i > 0; i--) {
        const j: number = Math.floor(Math.random() * (i + 1));
        const tmp: number = pool[i];
        pool[i] = pool[j];
        pool[j] = tmp;
      }
      if (!BoardModel.hasAnyMatch(pool) && BoardModel.hasValidMove(pool)) {
        return pool;
      }
    }
    return board.slice();
  }
}
