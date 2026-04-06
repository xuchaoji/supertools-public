import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { CalcMsgData } from '../model/CalcMsgData';
import { CommonViewModel } from '../viewmodel/CommonViewModel';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

const TAG: string = 'CalcWorkerTag'
/**
 * Defines the event handler to be called when the worker thread receives a message sent by the host thread.
 * The event handler is executed in the worker thread.
 *
 * @param event message data
 */
workerPort.onmessage = (event: MessageEvents) => {
  console.log(TAG, `onmessage: ${event.data.action}`)
  if (event.data.action === 'start') {
    CommonViewModel.getInstance().isWorkerRunning = true;
    CommonViewModel.getInstance().maxCalcCount = event.data.maxCalcCount;
    // 发送日志到主线程
    workerPort.postMessage({
      type: 'log',
      message: '开始执行高负载计算...'
    });

    setInterval(() => {
      try {
        const calcResult = heavyCalculation();

        // 发送计算结果到主线程
        if (CommonViewModel.getInstance().canPostToMain()) {
          workerPort.postMessage({
            type: 'log',
            message: `计算完成，耗时 ${calcResult.duration.toFixed(2)} 秒，结果=${calcResult.result}`
          } as CalcMsgData);
        }
      } catch (error) {
        workerPort.postMessage({
          type: 'log',
          message: `计算错误: ${error.message}`
        } as CalcMsgData);
      }
    }, 16)
  }

  if(event.data.action === 'stop') {
    CommonViewModel.getInstance().isWorkerRunning = false;
  }
}

/**
 * Defines the event handler to be called when the worker receives a message that cannot be deserialized.
 * The event handler is executed in the worker thread.
 *
 * @param event message data
 */
workerPort.onmessageerror = (event: MessageEvents) => {
  console.error(TAG, `Worker error: ${event.data}`);
};

/**
 * Defines the event handler to be called when an exception occurs during worker execution.
 * The event handler is executed in the worker thread.
 *
 * @param event error message
 */
workerPort.onerror = (event: ErrorEvent) => {
  console.error(TAG, `Worker error: ${event.message}`);
  workerPort.postMessage({
    type: 'log',
    message: `Worker发生错误: ${event.message}`
  } as CalcMsgData);

};

// 定义计算结果的数据结构
class CalculationResult {
  result: number = 0;
  duration: number = 0;
}

// 执行耗时计算的函数
function heavyCalculation() {
  // 模拟高负载计算 - 斐波那契数列
  let fibonacci: (n: number) => number = (n: number): number => {
    if (n <= 1 || !CommonViewModel.getInstance().isWorkerRunning) {
      return n;
    }
    return fibonacci(n - 1) + fibonacci(n - 2);
  };

  const startTime = new Date().getTime();

  // 计算斐波那契数列（n=40大约需要1-2秒）
  const result = fibonacci(getRandomInt(10, CommonViewModel.getInstance().maxCalcCount));

  const endTime = new Date().getTime();
  const duration = (endTime - startTime) / 1000;

  // 创建结果对象
  const calcResult = new CalculationResult();
  calcResult.result = result;
  calcResult.duration = duration;

  return calcResult;
}

function getRandomInt(min: number, max: number): number {
  min = Math.ceil(min);   // 向上取整，确保整数
  max = Math.floor(max);  // 向下取整，确保整数
  return Math.floor(Math.random() * (max - min + 1)) + min;
}