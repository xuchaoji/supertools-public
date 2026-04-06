import worker from '@ohos.worker';

const workerPort = worker.workerPort;

let isRunning = false;
let currentIntensity = 0;
let globalResult = 0;

function runStressLoop() {
  // [关键优化 1] 进入函数立即检查状态，确保停止信号能第一时间截断递归
  if (!isRunning) {
    return;
  }

  const startTime = Date.now();
  const totalPeriod = 50; // 基准周期保持 50ms 确保 CPU 曲线平滑
  const busyTime = (currentIntensity / 100) * totalPeriod;

  // [关键优化 2] 在密集计算的 while 循环中加入 isRunning 检测
  // 这样即使在计算中途收到 STOP 信号，也能在几毫秒内退出循环
  while ((Date.now() - startTime) < busyTime) {
    if (!isRunning) break;

    // 执行计算任务
    for (let i = 0; i < 500; i++) {
      globalResult += Math.random() * Math.sqrt(i) + Math.sin(i);
    }
  }

  if (!isRunning) return;

  // 计算剩余休息时间
  const elapsed = Date.now() - startTime;
  let restTime = totalPeriod - elapsed;

  // [关键优化 3] 强制让路
  // 即使 restTime <= 0 (100% 负载)，也给 1ms 的 setTimeout。
  // 这 1ms 是给系统的“呼吸孔”，让 Event Loop 有机会处理外部传来的 onmessage 回调。
  const nextDelay = restTime > 0 ? restTime : 1;

  setTimeout(() => {
    runStressLoop();
  }, nextDelay);
}

workerPort.onmessage = (e) => {
  const data: ESObject = e.data;
  const action: ESObject = data.action;

  if (action === 'START') {
    if (!isRunning) {
      isRunning = true;
      currentIntensity = data.intensity || 50;
      runStressLoop();
    }
  } else if (action === 'UPDATE') {
    currentIntensity = data.intensity;
  } else if (action === 'STOP') {
    // [关键优化 4] 状态置反后，下一次 while 循环判断和函数入口判断会立即生效
    isRunning = false;
    currentIntensity = 0;
  }
}