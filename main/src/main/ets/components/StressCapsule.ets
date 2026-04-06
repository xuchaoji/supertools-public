import { hidebug } from '@kit.PerformanceAnalysisKit';
import { StressKernel } from '../capabilities/floatingstress/StressKernel';
// 引入公共拖拽处理类 (根据你的实际路径调整)
import { FloatDragHandler } from '../utils/FloatDragHandler';
import { StressRing } from './StressRing';

const MAX_VISUAL_MEM: number = Number(hidebug.getSystemMemInfo().totalMem) / 1024;

@ComponentV2
export struct StressCapsule {
  // --- 核心状态 (@Local 确保 V2 响应式刷新) ---
  @Local intensity: number = 0;
  @Local realCpu: number = 0;
  @Local realMem: number = 0;
  @Local isActive: boolean = false;

  // --- 内部逻辑变量 ---
  private timerId: number = -1;
  private kernel = StressKernel.getInstance();

  // --- 核心重构：一行代码引入完美拖拽能力 ---
  // 注意：传入的窗口名称必须与 StressFloatWindowManager 中创建的名字保持一致
  private dragHandler: FloatDragHandler = new FloatDragHandler('stress_capsule_float');

  // --- 强度调节变量 ---
  private adjustStartIntensity: number = 0;

  aboutToAppear() {
    // 1. 启动定时器刷新数据
    this.timerId = setInterval(() => {
      this.refreshStats();
    }, 1000);
    // 移除了冗余的 display density 获取逻辑
  }

  aboutToDisappear() {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
    }
    this.kernel.destroy();
  }

  private refreshStats() {
    try {
      const rawCpu = hidebug.getSystemCpuUsage();
      const rawPss = hidebug.getSystemMemInfo().totalMem - hidebug.getSystemMemInfo().availableMem;

      // V2 直接赋值即可触发 UI 刷新
      this.realCpu = rawCpu * 100;
      this.realMem = Number(rawPss) / 1024; // 转为 MB
    } catch (e) {
      console.error(`[StressCapsule] Stats error: ${JSON.stringify(e)}`);
    }
  }

  private toggleStress() {
    this.isActive = !this.isActive;
    if (this.isActive) {
      // 启动时，如果强度为0，默认给个 50
      const target = this.intensity <= 0 ? 50 : this.intensity;
      this.intensity = target;
      this.kernel.start(target);
    } else {
      // 停止后进度重置为50，避免重新启动无法拖动
      this.intensity = 50;
      this.kernel.stop();
    }
  }

  // 计算内存圆环的视觉进度
  private getMemVisualProgress(): number {
    return Math.min(100, (this.realMem / MAX_VISUAL_MEM) * 100);
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {

      // 层1: 动态背景条 (强度指示器)
      Row()
        .width(`${this.intensity}%`)
        .height('100%')
        .backgroundColor(this.isActive ? '#D32F2F' : '#43A047') // 红/绿
        .opacity(this.isActive ? 0.2 : 0) // 压测时显示背景
        .animation({ duration: 200, curve: Curve.EaseOut })
        .borderRadius(31)

      // 层2: 核心内容
      Row() {
        // [左侧区域] 窗口拖拽把手
        Stack({ alignContent: Alignment.Center }) {
          Column({ space: 3 }) {
            Rect().width(4).height(4).fill('#FFF').radius(2)
            Rect().width(4).height(4).fill('#FFF').radius(2)
            Rect().width(4).height(4).fill('#FFF').radius(2)
          }
        }
        .width(44)
        .height('100%')
        .backgroundColor('rgba(255,255,255,0.01)') // 增大触摸热区
        // --- 核心重构：一键接入拖拽 ---
        .onTouch((event: TouchEvent) => {
          this.dragHandler.handleTouch(event);
        })

        // 竖分割线
        Divider().vertical(true).height(24).color('rgba(255,255,255,0.2)')

        // [中间区域] 圆环数据显示 + 强度调节滑块
        Row({ space: 8 }) {
          // CPU 圆环
          StressRing({
            label: "CPU",
            value: this.realCpu,
            displayValue: `${this.realCpu.toFixed(0)}%`,
            isActive: this.isActive
          })

          // MEM 圆环
          StressRing({
            label: "MEM",
            value: this.getMemVisualProgress(),
            displayValue: `${this.realMem.toFixed(0)}`,
            isActive: true
          })
        }
        .borderRadius(32)
        .layoutWeight(1) // 撑满剩余空间
        .height('100%')
        .justifyContent(FlexAlign.Center)
        // 强度精准调节手势保留 (属于该组件的特有业务)
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
            .onActionStart((event) => {
              if (event) {
                this.adjustStartIntensity = this.intensity;
              }
            })
            .onActionUpdate((event) => {
              if (event) {
                const delta = event.offsetX * 0.5;
                let newIntensity = this.adjustStartIntensity + delta;
                newIntensity = Math.max(0, Math.min(100, newIntensity));
                this.intensity = Math.round(newIntensity);

                if (this.isActive) {
                  this.kernel.updateIntensity(this.intensity);
                }
              }
            })
        )

        // [右侧区域] 启停按钮
        Column() {
          Text(`${this.intensity.toFixed(0)}%`)
            .fontSize(8).fontWeight(FontWeight.Bold).fontColor('#99FFFFFF').margin({ bottom: 2 })

          Button({ type: ButtonType.Capsule }) {
            Text(this.isActive ? "■" : "▶")
              .fontSize(10).fontColor(Color.White)
          }
          .width(22).height(22)
          .backgroundColor(this.isActive ? '#99E53935' : '#9943A047')
          .onClick(() => this.toggleStress())
        }
        .width(48)
        .height('auto')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#991A1A1A')
    .backdropBlur(5)
    .borderRadius(32)
    .border({ width: 1, color: 'rgba(255,255,255,0.1)' })
    .shadow({ radius: 2, color: 'rgba(0,0,0,0.5)', offsetY: 1 })
  }
}