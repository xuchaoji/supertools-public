import worker from '@ohos.worker';
import { hidebug } from '@kit.PerformanceAnalysisKit';

export class StressKernel {
  private static instance: StressKernel;
  private workerPool: worker.ThreadWorker[] = [];

  // 【关键】确保这里是 6 或 8 (对应你的手机核心数)
  private readonly CORE_COUNT = 8;

  private _isRunning: boolean = false;

  private constructor() {}

  public static getInstance(): StressKernel {
    if (!StressKernel.instance) {
      StressKernel.instance = new StressKernel();
    }
    return StressKernel.instance;
  }

  public start(intensity: number) {
    if (this._isRunning) return;
    this._isRunning = true;

    // 清理旧资源
    this.terminateAll();

    console.info(`[StressKernel] 暴力模式启动: ${this.CORE_COUNT} 线程, 目标强度: ${intensity}%`);

    for (let i = 0; i < this.CORE_COUNT; i++) {
      try {
        const w = new worker.ThreadWorker('main/ets/workers/StressWorker');
        w.postMessage({ action: 'START', intensity: intensity });
        // 绑定错误监听，防止 Worker 挂了都没人知道
        w.onerror = (err) => {
          console.error(`[StressKernel] Worker Error: ${JSON.stringify(err)}`);
        }
        this.workerPool.push(w);
      } catch (e) {
        console.error(`[StressKernel] Worker 创建失败: ${e}`);
      }
    }
  }

  public updateIntensity(intensity: number) {
    if (!this._isRunning) return;
    this.workerPool.forEach(w => {
      w.postMessage({ action: 'UPDATE', intensity: intensity });
    });
  }

  public stop() {
    this._isRunning = false;
    // 强制杀进程，保证立刻停止
    this.terminateAll();
  }

  private terminateAll() {
    this.workerPool.forEach(w => {
      try {
        w.terminate();
      } catch (e) {}
    });
    this.workerPool = [];
  }

  public destroy() {
    this.stop();
  }
}