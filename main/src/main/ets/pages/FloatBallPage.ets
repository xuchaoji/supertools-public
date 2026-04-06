import { window, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ImmersiveGlassCard } from '../components/ImmersiveGlassCard';

@Entry
@Component
struct FloatBallPage {
  // 监听 WebServerUtil 通过 AppStorage 抛出的最近访问文件
  @StorageProp('RecentAccessFile') recentFile: string = 'Web运行中';

  private windowClass: window.Window | undefined = undefined;

  // --- 核心状态变量 ---
  private density: number = 1.0;
  private startTouchX: number = 0;
  private startTouchY: number = 0;
  private startWinX: number = 0;
  private startWinY: number = 0;
  private isDragging: boolean = false;

  aboutToAppear() {
    try {
      this.windowClass = window.findWindow("FloatBallWindow");
      let displayDef = display.getDefaultDisplaySync();
      this.density = displayDef.densityPixels;
    } catch (exception) {
      console.error('Find window failed: ' + JSON.stringify(exception));
    }
  }

  build() {
    Column() {
      Stack() {
        ImmersiveGlassCard({ zHeight: 1, zRadius: 32 })

        // --- 替换为跑马灯组件 ---
        Marquee({
          start: true,
          step: 4,
          loop: -1,
          fromStart: true,
          src: this.recentFile
        })
          .width('85%') // 留出一点边距，避免贴边
          .fontColor(Color.Black)
          .fontSize(10) // 悬浮球较小，字号相应调小
          .fontWeight(FontWeight.Medium)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .onTouch((event) => {
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
          if (!this.isDragging && (diffX > 5 || diffY > 5)) {
            this.isDragging = true;
          }

          let deltaX_vp = currentTouchX - this.startTouchX;
          let deltaY_vp = currentTouchY - this.startTouchY;

          let deltaX_px = deltaX_vp * this.density;
          let deltaY_px = deltaY_vp * this.density;

          let targetX = this.startWinX + deltaX_px;
          let targetY = this.startWinY + deltaY_px;

          this.windowClass.moveWindowTo(targetX, targetY).catch((err: Object) => {});
        }
      })
      .onClick(() => {
        if (!this.isDragging) {
          this.openMainApp();
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  openMainApp() {
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.startAbility({
      bundleName: context.abilityInfo.bundleName,
      abilityName: context.abilityInfo.name
    });
  }
}