import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppUtil } from '@pura/harmony-utils';
import nativeGame from 'libgame.so';
import { PageNames } from '../constant/PageNames';
import { AdType } from '../constant/AdType';
import { AdsKitPreferences } from '../utils/AdsKitPreferences';
import { SafeArea } from '../utils/SafeArea';
import { Toast } from '../utils/Toast';
import { FloatWindowUtil } from '../utils/FloatWindowUtil';
import { WebServerUtil } from '../utils/WebServerUtil';
import { WindowStageHolder } from '../utils/WindowStageHolder';
import { GameEngine, GameState, MOVE_LIMIT, TARGET_TOTAL } from '../game/GameEngine';
import { FrameBuffer } from '../game/GameRenderer';
import { AdOutcome, GameAdService } from '../game/GameAdService';
import { GameBannerConfig } from '../game/GameBannerConfig';
import { UI_CENTER, UI_LEFT, UI_RIGHT, UiRectBuffer, UiTextBuffer } from '../game/GameUi';

const TAG: string = 'GAME_DEMO';
/** 每次进程只自动播一次开屏，避免反复进出页面被广告糊脸。 */
let splashPlayed: boolean = false;

interface HitTarget {
  id: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

// 原生 UI 配色（0..1）
const C_TEXT: number[] = [1, 1, 1, 0.96];
const C_SUB: number[] = [0.62, 0.66, 0.74, 1];
const C_CARD: number[] = [1, 1, 1, 0.055];
const C_CARD_STRONG: number[] = [1, 1, 1, 0.10];
const C_BLUE: number[] = [0.16, 0.46, 0.96, 1];
const C_DARK_BTN: number[] = [0.15, 0.17, 0.23, 1];
const C_GOLD: number[] = [1, 0.82, 0.29, 1];
const C_DIM: number[] = [0, 0, 0, 0.66];
const C_DIALOG: number[] = [0.055, 0.065, 0.095, 0.99];
const C_DEBUG_BG: number[] = [0.035, 0.045, 0.07, 0.99];

/**
 * 模拟游戏页（整屏原生渲染）。
 *
 * 页面里只有一个 XComponent：棋盘用 GL 画，HUD / 按钮 / 弹窗 / 调试面板
 * 全部由 libgame.so 用 OH_Drawing 离屏画成透明纹理再叠加。
 * 因此开启“显示布局边界”时看不到任何游戏控件——和真实游戏引擎整屏自绘一致。
 *
 * 横幅广告通过独立子窗口显示（GameBannerPage），不进入本页布局树。
 */
@HMRouter({ pageUrl: PageNames.GAME_DEMO_PAGE })
@Entry
@ComponentV2
export struct GameDemoPage {
  private engine: GameEngine = new GameEngine();
  private frame: FrameBuffer = new FrameBuffer();
  private rects: UiRectBuffer = new UiRectBuffer(320);
  private texts: UiTextBuffer = new UiTextBuffer();
  private hits: HitTarget[] = [];
  private adService: GameAdService = GameAdService.getInstance();
  private timerId: number = -1;
  private density: number = 3;
  private W: number = 360;
  private H: number = 760;
  private boardX: number = 12;
  private boardY: number = 124;
  private boardSize: number = 336;
  private safeBottomPx: number = 0;
  private bannerH: number = 58;
  private bannerWin: window.Window | null = null;
  private showDebug: boolean = false;
  private forceMock: boolean = false;
  private adBusy: boolean = false;
  private adLog: string = '';
  private logVersion: number = 0;
  private lastUiKey: string = '';
  private hidFloatBall: boolean = false;
  private mainWindow: window.Window | null = null;

  aboutToAppear(): void {
    const d = display.getDefaultDisplaySync();
    this.density = d.densityPixels > 0 ? d.densityPixels : 3;
    this.safeBottomPx = this.parsePx(SafeArea.bottom());
    this.W = d.width / this.density;
    this.H = (d.height - AppUtil.getStatusBarHeight()) / this.density;
    this.computeLayout(this.W, this.H);
    this.engine.reset();

    if (WebServerUtil.getInstance().isRunning) {
      this.hidFloatBall = true;
      FloatWindowUtil.destroyFloatWindow();
    }
    this.adLog = this.adService.getLogText();
    this.applyStatusBar(true);
    this.timerId = setInterval(() => {
      this.onFrame();
    }, 16);
    if (!splashPlayed) {
      splashPlayed = true;
      setTimeout(() => {
        this.playSplash();
      }, 400);
    }
    this.showBannerWindow();
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    if (this.bannerWin !== null) {
      this.bannerWin.destroyWindow();
      this.bannerWin = null;
    }
    GameBannerConfig.onStatus = (_loaded: boolean): void => {};
    this.applyStatusBar(false);
    if (this.hidFloatBall && WebServerUtil.getInstance().isRunning) {
      this.hidFloatBall = false;
      FloatWindowUtil.showFloatWindow();
    }
  }

  /** 游戏页统一深色状态栏（白色图标），退出时恢复为透明/深色图标。 */
  private async applyStatusBar(dark: boolean): Promise<void> {
    try {
      if (this.mainWindow === null) {
        this.mainWindow = await window.getLastWindow(this.context());
      }
      await this.mainWindow.setWindowSystemBarProperties({
        statusBarColor: dark ? '#07090F' : '#00000000',
        statusBarContentColor: dark ? '#FFFFFF' : '#000000',
        navigationBarColor: '#00000000'
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, 'status bar update failed: %{public}s', JSON.stringify(e));
    }
  }

  private parsePx(value: string): number {
    const parsed: number = parseFloat(value.replace('px', ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private safeBottomVp(): number {
    return this.safeBottomPx / this.density;
  }

  private computeLayout(w: number, h: number): void {
    this.W = w;
    this.H = h;
    const margin: number = 12;
    this.boardSize = w - margin * 2;
    this.boardX = margin;
    // 顶部栏 42 + HUD 58 + 间距
    this.boardY = 6 + 42 + 8 + 58 + 10;
    this.engine.setBoard(this.boardX / this.W, this.boardY / this.H,
      this.boardSize / this.W, this.boardSize / this.H);
    this.lastUiKey = '';
  }

  // ===================== 帧循环 =====================

  private onFrame(): void {
    const now: number = Date.now();
    const size: Float32Array = nativeGame.getSurfaceSize();
    if (size[0] > 0 && size[1] > 0) {
      const wVp: number = size[0] / this.density;
      const hVp: number = size[1] / this.density;
      if (Math.abs(wVp - this.W) > 0.5 || Math.abs(hVp - this.H) > 0.5) {
        this.computeLayout(wVp, hVp);
      }
    }
    this.pollInput();
    this.engine.tick();
    this.engine.buildFrame(this.frame, now);
    this.frame.flush();

    const key: string = this.uiKey();
    if (key !== this.lastUiKey) {
      this.lastUiKey = key;
      this.rebuildUi();
      this.rects.flush();
      this.texts.flush();
    }
  }

  private uiKey(): string {
    return `${this.engine.movesLeft},${this.engine.targetLeft},${this.engine.score},` +
      `${this.engine.state},${this.engine.banner},${this.showDebug},${this.adBusy},` +
      `${this.forceMock},${this.logVersion},${Math.round(this.W)}x${Math.round(this.H)}`;
  }

  // ===================== 输入 =====================

  private pollInput(): void {
    const touch: Float32Array = nativeGame.pollTouch();
    if (touch[0] > 0.5) {
      const x: number = touch[1] * this.W;
      const y: number = touch[2] * this.H;
      const id: string = this.hitTest(x, y);
      if (id.length > 0) {
        this.onAction(id);
        return;
      }
      if (!this.showDebug) {
        this.engine.onTouchDown(touch[1], touch[2]);
      }
    }
    if (touch[3] > 0.5 && !this.showDebug) {
      this.engine.onTouchMove(touch[4], touch[5]);
    }
    if (touch[6] > 0.5) {
      this.engine.onTouchUp();
    }
  }

  private hitTest(x: number, y: number): string {
    for (let i: number = this.hits.length - 1; i >= 0; i--) {
      const t: HitTarget = this.hits[i];
      if (x >= t.x && x <= t.x + t.w && y >= t.y && y <= t.y + t.h) {
        return t.id;
      }
    }
    return '';
  }

  private addHit(id: string, x: number, y: number, w: number, h: number): void {
    this.hits.push({ id: id, x: x, y: y, w: w, h: h });
  }

  private onAction(id: string): void {
    this.lastUiKey = '';
    switch (id) {
      case 'back':
        HMRouterMgr.pop();
        break;
      case 'debug':
        this.showDebug = !this.showDebug;
        break;
      case 'dbg_close':
        this.showDebug = false;
        break;
      case 'revive':
        this.playRewarded('revive');
        break;
      case 'coin':
        this.playRewarded('coin');
        break;
      case 'restart':
        this.engine.reset();
        break;
      case 'next':
        this.nextLevel();
        break;
      case 'shuffle':
        this.engine.debugShuffle();
        break;
      case 'dbg_auto':
        this.engine.debugAutoMove();
        break;
      case 'dbg_lose':
        this.engine.forceLose();
        this.showDebug = false;
        break;
      case 'dbg_win':
        this.engine.forceWin();
        this.showDebug = false;
        break;
      case 'dbg_reset':
        this.engine.reset();
        break;
      case 'dbg_shuffle':
        this.engine.debugShuffle();
        break;
      case 'dbg_reward':
        this.playRewarded('revive');
        break;
      case 'dbg_inter':
        this.playInterstitial();
        break;
      case 'dbg_splash':
        this.playSplash();
        break;
      case 'dbg_mock':
        this.forceMock = !this.forceMock;
        this.adService.setForceMock(this.forceMock);
        this.refreshAdLog();
        break;
      default:
        break;
    }
  }

  // ===================== 广告 =====================

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private refreshAdLog(): void {
    this.adLog = this.adService.getLogText();
    this.logVersion++;
  }

  private async playSplash(): Promise<void> {
    if (this.adBusy) {
      return;
    }
    this.adBusy = true;
    this.engine.pause();
    const outcome: AdOutcome = await this.adService.showSplash(this.context());
    this.adBusy = false;
    this.refreshAdLog();
    if (this.engine.state === GameState.PAUSED) {
      this.engine.resume();
    }
    Toast.show(outcome.mock ? `开屏 Mock：${outcome.message}` : outcome.message);
  }

  private async playInterstitial(): Promise<void> {
    if (this.adBusy) {
      return;
    }
    this.adBusy = true;
    this.engine.pause();
    const outcome: AdOutcome = await this.adService.showInterstitial(this.context());
    this.adBusy = false;
    this.refreshAdLog();
    if (this.engine.state === GameState.PAUSED) {
      this.engine.resume();
    }
    if (outcome.mock) {
      Toast.show(`插屏 Mock：${outcome.message}`);
    }
  }

  private async playRewarded(mode: string): Promise<void> {
    if (this.adBusy) {
      return;
    }
    this.adBusy = true;
    this.engine.pause();
    const outcome: AdOutcome = await this.adService.showRewarded(this.context());
    this.adBusy = false;
    this.refreshAdLog();
    if (outcome.rewarded) {
      if (mode === 'coin') {
        this.engine.addBonus(50);
        if (this.engine.state === GameState.PAUSED) {
          this.engine.resume();
        }
        Toast.show('奖励 +50 分');
      } else {
        this.engine.revive();
        Toast.show('复活成功，+5 步');
      }
      return;
    }
    if (this.engine.state === GameState.PAUSED) {
      this.engine.resume();
    }
    Toast.show(outcome.message);
  }

  private async nextLevel(): Promise<void> {
    if (this.adBusy) {
      return;
    }
    this.adBusy = true;
    const outcome: AdOutcome = await this.adService.showInterstitial(this.context());
    this.adBusy = false;
    this.refreshAdLog();
    this.engine.reset();
    if (outcome.mock) {
      Toast.show('插屏 Mock 完成，进入下一关');
    }
  }

  // ===================== 横幅子窗口 =====================

  private async showBannerWindow(): Promise<void> {
    const stage: window.WindowStage | null = WindowStageHolder.get();
    const adId: string = AdsKitPreferences.getId(AdType.BANNER);
    if (stage === null || adId.length === 0) {
      this.bannerH = 0;
      this.lastUiKey = '';
      return;
    }
    GameBannerConfig.adId = adId;
    const d = display.getDefaultDisplaySync();
    const hPx: number = Math.round(58 * this.density);
    const bannerY: number = d.height - hPx - this.safeBottomPx;
    // 没有 ad 时把子窗口挪到屏幕外（Window 没有 hide API），避免底部留空白条
    GameBannerConfig.onStatus = (loaded: boolean): void => {
      this.bannerH = loaded ? 58 : 0;
      if (this.bannerWin !== null) {
        this.bannerWin.moveWindowTo(0, loaded ? bannerY : d.height + 20);
      }
      this.lastUiKey = '';
    };
    try {
      const win: window.Window = await stage.createSubWindow('game_banner_win');
      await win.setUIContent('pages/GameBannerPage');
      win.setWindowBackgroundColor('#0A0D14');
      await win.setWindowFocusable(false);
      await win.resize(d.width, hPx);
      await win.moveWindowTo(0, bannerY);
      await win.showWindow();
      this.bannerWin = win;
      this.bannerH = 58;
      hilog.info(0x0000, TAG, 'banner subwindow ready');
    } catch (e) {
      hilog.error(0x0000, TAG, 'banner subwindow failed: %{public}s', JSON.stringify(e));
      this.bannerH = 0;
    }
    this.lastUiKey = '';
  }

  // ===================== 原生 UI 显示列表 =====================

  private addRect(x: number, y: number, w: number, h: number, c: number[], radiusVp: number): void {
    const shortSide: number = Math.min(w, h);
    const radius: number = shortSide > 0 ? Math.min(0.5, radiusVp / shortSide) : 0;
    this.rects.add(x / this.W, y / this.H, w / this.W, h / this.H, c[0], c[1], c[2], c[3], radius);
  }

  private addText(text: string, x: number, y: number, size: number, c: number[],
    align: number, bold: boolean): void {
    this.texts.add(text, x / this.W, y / this.H, size / this.H, c[0], c[1], c[2], c[3], align, bold);
  }

  private rebuildUi(): void {
    this.rects.reset();
    this.texts.reset();
    this.hits = [];
    const W: number = this.W;
    const H: number = this.H;

    // 弹窗/调试面板打开时只画遮罩 + 面板本身：
    // 原生层是先画所有矩形、再画所有文本，若保留底层 HUD 的文本，
    // 它们会盖在半透明遮罩上（看起来"没变暗"）。直接不画底层最干净。
    if (this.showDebug) {
      this.debugPanel(W, H);
      return;
    }
    if (this.engine.state === GameState.LOSE) {
      this.loseDialog(W, H);
      return;
    }
    if (this.engine.state === GameState.WIN) {
      this.winDialog(W, H);
      return;
    }

    // ---------- 顶部栏 ----------
    this.addRect(8, 4, 40, 40, C_CARD, 20);
    this.addText('‹', 28, 8, 24, C_TEXT, UI_CENTER, false);
    this.addHit('back', 4, 0, 48, 48);
    this.addText('消除大师', W / 2, 8, 17, C_TEXT, UI_CENTER, true);
    this.addText('原生渲染 · 第 1 关', W / 2, 30, 9, C_SUB, UI_CENTER, false);
    this.addText('DEBUG', W - 12, 16, 9, this.showDebug ? C_GOLD : C_SUB, UI_RIGHT, false);
    this.addHit('debug', W - 72, 2, 68, 40);

    // ---------- HUD ----------
    const hudY: number = 56;
    const hudH: number = 58;
    const hudGap: number = 8;
    const pillW: number = (W - 24 - hudGap * 2) / 3;
    const values: string[] = [
      `${this.engine.targetLeft}/${TARGET_TOTAL}`,
      `${this.engine.movesLeft}/${MOVE_LIMIT}`,
      `${this.engine.score}`
    ];
    const labels: string[] = ['目标', '步数', '得分'];
    const colors: number[][] = [[0.48, 0.72, 1, 1], [1, 0.76, 0.29, 1], [0.48, 0.89, 0.61, 1]];
    for (let i: number = 0; i < 3; i++) {
      const x: number = 12 + i * (pillW + hudGap);
      this.addRect(x, hudY, pillW, hudH, C_CARD, 14);
      this.addText(values[i], x + pillW / 2, hudY + 8, 20, colors[i], UI_CENTER, true);
      this.addText(labels[i], x + pillW / 2, hudY + 37, 9, C_SUB, UI_CENTER, false);
    }

    // ---------- 棋盘下方提示 ----------
    const hintY: number = this.boardY + this.boardSize + 5;
    const hasBanner: boolean = this.engine.banner.length > 0;
    this.addText(hasBanner ? this.engine.banner : '滑动或点选相邻方块交换',
      W / 2, hintY, 10, hasBanner ? C_GOLD : C_SUB, UI_CENTER, false);

    // ---------- 关卡卡 ----------
    const cardY: number = hintY + 22;
    this.addRect(12, cardY, W - 24, 48, C_CARD, 14);
    this.addText('第 1 关', 24, cardY + 8, 12, C_TEXT, UI_LEFT, true);
    this.addText(`目标 ${TARGET_TOTAL} 个 · 上限 ${MOVE_LIMIT} 步 · 用完可看广告复活`,
      24, cardY + 27, 9, C_SUB, UI_LEFT, false);

    // ---------- 金币 / 激励视频入口（真实游戏里最常见的常驻广告位） ----------
    const coinY: number = cardY + 60;
    this.addRect(12, coinY, W - 24, 52, [0.20, 0.16, 0.06, 1], 14);
    this.addText('看视频领金币', 26, coinY + 9, 13, C_GOLD, UI_LEFT, true);
    this.addText('+50 分', W - 26, coinY + 11, 12, C_GOLD, UI_RIGHT, false);
    this.addHit('coin', 12, coinY, W - 24, 52);

    // ---------- 底部操作（原生按钮） ----------
    const btnY: number = H - this.safeBottomVp() - this.bannerH - 56;
    const btnW: number = (W - 32) / 2;
    const btnH: number = 46;
    this.addRect(12, btnY, btnW, btnH, C_CARD_STRONG, 14);
    this.addText('洗牌', 12 + btnW / 2, btnY + 13, 14, C_TEXT, UI_CENTER, true);
    this.addHit('shuffle', 12, btnY, btnW, btnH);
    this.addRect(20 + btnW, btnY, btnW, btnH, C_CARD_STRONG, 14);
    this.addText('重玩', 20 + btnW + btnW / 2, btnY + 13, 14, C_TEXT, UI_CENTER, true);
    this.addHit('restart', 20 + btnW, btnY, btnW, btnH);
  }

  private loseDialog(W: number, H: number): void {
    this.addRect(0, 0, W, H, C_DIM, 0);
    const cw: number = W * 0.86;
    const ch: number = 238;
    const cx: number = (W - cw) / 2;
    const cy: number = H * 0.30;
    this.addRect(cx, cy, cw, ch, C_DIALOG, 20);
    this.addText('步数用完了', W / 2, cy + 20, 20, C_TEXT, UI_CENTER, true);
    this.addText(`还差 ${this.engine.targetLeft} 个目标，看一段激励视频再给 ${5} 步`,
      W / 2, cy + 58, 10, C_SUB, UI_CENTER, false);
    this.addRect(cx + 18, cy + 92, cw - 36, 46, C_BLUE, 14);
    this.addText(this.adBusy ? '加载中…' : '看广告 +5 步', W / 2, cy + 105, 14, C_TEXT, UI_CENTER, true);
    this.addHit('revive', cx + 18, cy + 92, cw - 36, 46);
    this.addRect(cx + 18, cy + 150, cw - 36, 44, C_DARK_BTN, 14);
    this.addText('重新开始', W / 2, cy + 162, 13, C_TEXT, UI_CENTER, true);
    this.addHit('restart', cx + 18, cy + 150, cw - 36, 44);
  }

  private winDialog(W: number, H: number): void {
    this.addRect(0, 0, W, H, C_DIM, 0);
    const cw: number = W * 0.86;
    const ch: number = 238;
    const cx: number = (W - cw) / 2;
    const cy: number = H * 0.30;
    this.addRect(cx, cy, cw, ch, C_DIALOG, 20);
    this.addText('过关！', W / 2, cy + 20, 22, C_GOLD, UI_CENTER, true);
    this.addText(`得分 ${this.engine.score} · 目标全部消除`, W / 2, cy + 60, 10, C_SUB, UI_CENTER, false);
    this.addRect(cx + 18, cy + 92, cw - 36, 46, C_BLUE, 14);
    this.addText(this.adBusy ? '加载中…' : '下一关', W / 2, cy + 105, 14, C_TEXT, UI_CENTER, true);
    this.addHit('next', cx + 18, cy + 92, cw - 36, 46);
    this.addRect(cx + 18, cy + 150, cw - 36, 44, C_DARK_BTN, 14);
    this.addText('重玩本关', W / 2, cy + 162, 13, C_TEXT, UI_CENTER, true);
    this.addHit('restart', cx + 18, cy + 150, cw - 36, 44);
  }

  private debugPanel(W: number, H: number): void {
    this.addRect(0, 0, W, H, C_DIM, 0);
    const px: number = W * 0.07;
    const pw: number = W * 0.86;
    const py: number = H * 0.07;
    const rowH: number = 30;
    const ids: string[] = ['dbg_auto', 'dbg_lose', 'dbg_win', 'dbg_reset', 'dbg_shuffle',
      'dbg_reward', 'dbg_inter', 'dbg_splash', 'dbg_mock'];
    const labels: string[] = ['自动走一步（找可消除）', '步数归零（测复活）', '直接通关（测插屏）',
      '重置关卡', '洗牌', '看激励视频', '看插屏广告', '看开屏广告',
      this.forceMock ? 'Mock 模式：开' : 'Mock 模式：关'];
    const logLines: string[] = this.adLog.split('\n').slice(0, 4);
    const logH: number = 20 + logLines.length * 14;
    const ph: number = 44 + labels.length * (rowH + 4) + logH + 12;

    this.addRect(px, py, pw, ph, C_DEBUG_BG, 16);
    this.addText('广告 / 关卡调试', px + 14, py + 12, 13, C_TEXT, UI_LEFT, true);
    this.addText('×', px + pw - 24, py + 6, 20, C_SUB, UI_CENTER, false);
    this.addHit('dbg_close', px + pw - 46, py + 2, 42, 36);

    for (let i: number = 0; i < labels.length; i++) {
      const y: number = py + 44 + i * (rowH + 4);
      this.addRect(px + 12, y, pw - 24, rowH, C_CARD_STRONG, 9);
      this.addText(labels[i], px + 22, y + 7, 11, C_TEXT, UI_LEFT, false);
      this.addHit(ids[i], px + 12, y, pw - 24, rowH);
    }
    const logY: number = py + 44 + labels.length * (rowH + 4) + 8;
    this.addText('广告回调日志', px + 14, logY, 9, C_SUB, UI_LEFT, false);
    for (let i: number = 0; i < logLines.length; i++) {
      this.addText(logLines[i], px + 14, logY + 16 + i * 14, 8.5, C_SUB, UI_LEFT, false);
    }
  }

  build() {
    // ArkUI 要求 @Entry 的 build 根节点是容器；这里只放一个全屏 XComponent，
    // 所有游戏 UI 都在它的 Surface 里原生绘制，布局树中没有其它游戏控件。
    Stack() {
      XComponent({
        id: 'gameSurface',
        type: XComponentType.SURFACE,
        libraryname: 'game'
      })
        .width('100%')
        .height('100%')
        .backgroundColor('#07090F')
        .onLoad((ctx?: object) => {
          hilog.info(0x0000, TAG, 'XComponent onLoad ctx=%{public}s', ctx ? 'yes' : 'no');
          if (ctx) {
            nativeGame.attach(ctx);
          }
          this.onFrame();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#07090F')
  }
}
