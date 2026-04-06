// 主页面：Index.ets
import worker, { MessageEvents } from '@ohos.worker';
import { BusinessError } from '@ohos.base';
import { HMRouter } from '@hadss/hmrouter';
import { PageNames } from '../constant/PageNames';
import { CalcMsgData } from '../model/CalcMsgData';
import { StatusIndicator } from '../widgets/StatusIndicator';
import { hidebug } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'CalcPageTag';

const MAX_WK_CNT: number = 12;

const MAX_CALC_CNT: number = 100;

const ADD_LOG_INTERVAL: number = 200;

@Entry
@ComponentV2
@HMRouter({ pageUrl: PageNames.CALC_PAGE })
export struct CalcPage {
  @Local workers: worker.ThreadWorker[] = [];
  @Local workerCount: number = 2;
  @Local maxCalcCount: number = 30;
  @Local isRunning: boolean = false;
  @Local cpuLoad: number = 0;
  @Local memoryUsage: number = 0;
  @Local temperature: number = 28;
  @Local logs: string[] = [];
  // 设备状态模拟
  private timerId: number = 0;
  private addLogTime: number = 0;

  @Monitor('cpuLoad')
  onCpuLoadChange() {
    console.log(TAG, `onCpuLoadChange: ${this.cpuLoad}`);
  }

  aboutToAppear(): void {
    this.startMonitoring();
  }

  // 启动设备状态监控
  startMonitoring() {
    if (this.timerId) {
      clearInterval(this.timerId);
    }

    this.timerId = setInterval(() => {
      // CPU负载变化
      this.cpuLoad = Number(hidebug.getSystemCpuUsage().toFixed(2)) * 100;


      // 内存使用
      this.memoryUsage = Number((Number(hidebug.getSystemMemInfo().totalMem.toString()) - Number(hidebug.getSystemMemInfo().availableMem.toString())) / Number(hidebug.getSystemMemInfo().totalMem.toString())) * 100;
      console.log(TAG, `memory usage: ${this.memoryUsage}}`)

      // 模拟温度变化
      this.temperature = 28 + Math.min(22, this.workers.length * 3 + Math.random() * 5);
    }, 1000);
  }

  // 添加日志（优化性能）
  addLog(message: string) {
    /*if (Date.now() - this.addLogTime <= ADD_LOG_INTERVAL) {
      return;
    }*/
    this.addLogTime = Date.now();
    const timestamp = new Date().toLocaleTimeString();

    // todo display more logs
    if (this.logs.length === 0) {
      this.logs.push(message)
    } else {
      this.logs[0] = message;
    }
  }

  // 启动Worker（优化消息处理）
  startWorkers() {
    console.log(TAG, `startWker`)
    if (this.isRunning) {
      return;
    }

    this.workers = [];
    this.isRunning = true;

    for (let i = 0; i < this.workerCount; i++) {
      try {
        const wk = new worker.ThreadWorker('main/ets/workers/CalcWorker');
        this.workers.push(wk);

        // 使用箭头函数保持this上下文
        wk.onmessage = (e: MessageEvents) => {
          console.log(TAG, `onMessage: ${JSON.stringify(e.data)}`)
          const data: CalcMsgData = e.data;

          if (data.type === 'log') {
            // 使用异步更新避免阻塞UI
            setTimeout(() => {
              this.addLog(`Worker ${i + 1}: ${data.message}`);
            }, 0);
          }
        };

        // 监听Worker错误
        wk.onerror = (e) => {
          setTimeout(() => {
            this.addLog(`Worker ${i + 1} 错误: ${e.message}`);
          }, 0);
        };

        // 启动计算任务
        wk.postMessage({ action: 'start', maxCalcCount: this.maxCalcCount, id: i });
        this.addLog(`Worker ${i + 1} 已启动`);
      } catch (error) {
        const err: BusinessError = error as BusinessError;
        this.addLog(`创建Worker失败: ${err.message}`);
      }
    }
  }

  // 停止所有Worker
  stopWorkers() {
    if (!this.isRunning) {
      return;
    }

    this.workers.forEach((wk, index) => {
      try {
        wk.postMessage({ action: 'stop' })
        wk.terminate();
        this.addLog(`Worker ${index + 1} 已停止`);
      } catch (error) {
        const err: BusinessError = error as BusinessError;
        this.addLog(`停止Worker失败: ${err.message}`);
      }
    });

    this.workers = [];
    this.isRunning = false;
    this.cpuLoad = 0;
    this.memoryUsage = 0;
    this.temperature = 28;
    this.addLog("所有Worker已停止(已提交的计算任务会继续执行)");
  }

  // 组件销毁时清理资源
  aboutToDisappear() {
    this.stopWorkers();
    clearInterval(this.timerId);
  }

  build() {
    Column() {
      // 标题
      Text('设备高负载模拟器')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 10 });

      // 状态指示器
      Row() {
        StatusIndicator({
          label: 'CPU',
          value: this.cpuLoad,
          color: '#FF6B6B'
        });
        StatusIndicator({
          label: '内存',
          value: this.memoryUsage,
          color: '#4ECDC4'
        });
        /*StatusIndicator({
          label: '温度',
          value: this.temperature,
          color: '#FFD166'
        });*/
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
      .margin({ bottom: 20 });

      // 控制面板
      ControlPanel({
        workerCount: this.workerCount,
        isRunning: this.isRunning,
        maxCalcCount: this.maxCalcCount,
        onCalcMaxCountChange: (maxCalcCount) => {
          this.maxCalcCount = maxCalcCount
        },
        onWorkerCountChange: (count: number) => {
          this.workerCount = count;
        },
        onStart: () => {
          this.startWorkers();
        },
        onStop: () => {
          this.stopWorkers();
        }
      })
        .margin({ bottom: 20 });

      // 日志面板
      LogPanel({ logs: this.logs })
        .margin({ bottom: 20 });
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('sys.color.background_primary'));
  }
}

// 控制面板组件
@ComponentV2
struct ControlPanel {
  @Param @Require workerCount: number;
  @Param @Require maxCalcCount: number;
  @Param @Require isRunning: boolean;
  @Event onCalcMaxCountChange: (maxCalcCount: number) => void = (maxCalcCount) => {
  };
  @Event onWorkerCountChange: (count: number) => void = (count) => {
  };
  @Event onStart: () => void = () => {
  };
  @Event onStop: () => void = () => {
  };

  build() {
    Column() {
      // Worker数量控制
      Row() {
        Text('Worker数量:')
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .margin({ right: 12 });

        Button('-')
          .width(40)
          .height(40)
          .fontSize(18)
          .opacity(this.isRunning ? 0.5 : 1)
          .onClick(() => {
            if (!this.isRunning && this.workerCount > 1) {
              this.onWorkerCountChange(this.workerCount - 1);
            }
          });

        Text(this.workerCount.toString())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .width(60)
          .textAlign(TextAlign.Center);

        Button('+')
          .width(40)
          .height(40)
          .fontSize(18)
          .opacity(this.isRunning ? 0.5 : 1)
          .onClick(() => {
            if (!this.isRunning && this.workerCount < MAX_WK_CNT) {
              this.onWorkerCountChange(this.workerCount + 1);
            }
          });
      }
      .margin({ bottom: 16 });

      Row() {
        Column({ space: '8vp' }) {
          Text('计算轮数:')
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .margin({ right: 12 });
          Text('越大越耗时，停止越慢')
            .fontSize(8)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ right: 12 });
        }


        Button('-')
          .width(40)
          .height(40)
          .fontSize(18)
          .opacity(this.isRunning ? 0.5 : 1)
          .onClick(() => {
            if (!this.isRunning && this.maxCalcCount > 10) {
              this.onCalcMaxCountChange(this.maxCalcCount - 10);
            }
          });

        Text(this.maxCalcCount.toString())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .width(60)
          .textAlign(TextAlign.Center);

        Button('+')
          .width(40)
          .height(40)
          .fontSize(18)
          .opacity(this.isRunning ? 0.5 : 1)
          .onClick(() => {
            if (!this.isRunning && this.maxCalcCount < MAX_CALC_CNT) {
              this.onCalcMaxCountChange(this.maxCalcCount + 10);
            }
          });
      }
      .margin({ bottom: 16 });

      // 控制按钮
      Row() {
        Button(this.isRunning ? '停止负载' : '启动负载')
          .width(140)
          .height(45)
          .fontSize(18)
          .fontColor(Color.White)
          .backgroundColor(this.isRunning ? '#FF6B6B' : '#4CAF50')
          .onClick(() => {
            if (this.isRunning) {
              this.onStop();
            } else {
              this.onStart();
            }
          });
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
    .shadow({
      radius: 4,
      color: '#00000020',
      offsetX: 0,
      offsetY: 2
    });
  }
}

// 日志面板组件
@Component
struct LogPanel {
  @Prop logs: string[] = [];

  build() {
    Column() {
      Text('运行日志(非实时)')
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
        .margin({ bottom: 8 });

      // todo 日志列表
      Text(this.logs[0])
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .padding(8)
        .width('100%')
        .height('auto')
    }
    .width('100%')
    .height('auto')
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
    .shadow({
      radius: 4,
      color: '#00000020',
      offsetX: 0,
      offsetY: 2
    });
  }
}