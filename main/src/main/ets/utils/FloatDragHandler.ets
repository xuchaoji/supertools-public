import { window, display } from '@kit.ArkUI';

export class FloatDragHandler {
  private windowName: string;
  private windowClass: window.Window | undefined = undefined;
  private density: number = 1.0;

  private startTouchX: number = 0;
  private startTouchY: number = 0;
  private startWinX: number = 0;
  private startWinY: number = 0;
  private isDragging: boolean = false;

  constructor(windowName: string) {
    this.windowName = windowName;
    this.init();
  }

  private init(): void {
    try {
      const d = display.getDefaultDisplaySync();
      this.density = d.densityPixels;
      this.windowClass = window.findWindow(this.windowName); // API 12 同步调用
    } catch (err) {
      console.error(`[FloatDragHandler] Init failed: ${JSON.stringify(err)}`);
    }
  }

  public handleTouch(event: TouchEvent): void {
    if (!this.windowClass) return;
    let currentTouchX = event.touches[0].displayX;
    let currentTouchY = event.touches[0].displayY;

    if (event.type === TouchType.Down) {
      this.isDragging = false;
      this.startTouchX = currentTouchX;
      this.startTouchY = currentTouchY;
      let windowRect = this.windowClass.getWindowProperties().windowRect;
      this.startWinX = windowRect.left;
      this.startWinY = windowRect.top;
    }
    else if (event.type === TouchType.Move) {
      let diffX = Math.abs(currentTouchX - this.startTouchX);
      let diffY = Math.abs(currentTouchY - this.startTouchY);
      if (!this.isDragging && (diffX > 2 || diffY > 2)) {
        this.isDragging = true;
      }
      if (this.isDragging) {
        let deltaX_px = (currentTouchX - this.startTouchX) * this.density;
        let deltaY_px = (currentTouchY - this.startTouchY) * this.density;
        this.windowClass.moveWindowTo(this.startWinX + deltaX_px, this.startWinY + deltaY_px).catch(() => {});
      }
    }
  }
}