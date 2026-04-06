
const POST_MAIN_INTERVAL: number = 150;

@ObservedV2
export class CommonViewModel {
  private static instance: CommonViewModel;
  private _workerPostToMainTime: number = 0;
  private _isWorkerRunning: boolean = true;
  maxCalcCount: number = 30;
  @Trace privacyLoadingProgress:number = 0;
  @Trace
  private _cpuStressOn: boolean = false;

  public set cpuStressOn(value: boolean) {
    this._cpuStressOn = value;
  }

  public get cpuStressOn(): boolean {
    return this._cpuStressOn;
  }

  @Trace
  private _floatingClockOn: boolean = false;

  public set floatingClockOn(value: boolean) {
    this._floatingClockOn = value;
  }

  public get floatingClockOn(): boolean {
    return this._floatingClockOn;
  }

  public static getInstance() {
    if (!CommonViewModel.instance) {
      CommonViewModel.instance = new CommonViewModel();
    }
    return CommonViewModel.instance;
  }

  public set isWorkerRunning(value: boolean) {
    this._isWorkerRunning = value;
  }

  public get isWorkerRunning(): boolean {
    return this._isWorkerRunning;
  }

  public set workerPostToMainTime(value: number) {
    this._workerPostToMainTime = value;
  }

  public get workerPostToMainTime(): number {
    return this._workerPostToMainTime;
  }

  public canPostToMain() {
    if (Date.now() - this.workerPostToMainTime < POST_MAIN_INTERVAL) {
      return false;
    } else {
      this.workerPostToMainTime = Date.now();
      return true;
    }
  }
}