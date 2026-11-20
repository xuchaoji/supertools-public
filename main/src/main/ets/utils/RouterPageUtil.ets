import { router } from '@kit.ArkUI';
import { JSON } from '@kit.ArkTS';

/**
 * router 页面栈快照。
 *
 * router 的索引从 1 开始计数，1 = 栈底页面（本应用是 `pages/Index`）。
 */
export class RouterStackInfo {
  /** 当前页面路径，例如 pages/RouterDemoPage */
  path: string = '';
  /** 当前页在栈中的索引（从 1 开始） */
  index: number = 0;
  /** 页面栈深度 */
  length: number = 0;
  /** 栈快照文本：每行 `索引. 页面路径`（底 → 顶） */
  chain: string = '';
}

/**
 * 系统 router 演示页的公共读取工具。
 *
 * 只封装 `router.getParams()/getState()/getLength()/getStateByIndex()` 这几个
 * 只读能力，避免每个演示页各写一份同样的格式化代码。
 */
export class RouterPageUtil {
  /**
   * 拼接页面的完整路径。
   *
   * 实测部分系统版本上 `RouterState.path` 返回的是页面目录（如 `pages/`），
   * 文件名在 `RouterState.name` 中；这里兼容两种情况：
   * - path 以 `/` 结尾：`pages/` + `RouterMainPage` -> `pages/RouterMainPage`
   * - path 已是完整路径：原样返回
   */
  private static fullPath(path: string, name: string): string {
    if (path === '') {
      return name;
    }
    return path.endsWith('/') ? `${path}${name}` : path;
  }

  /** 当前页 router.getParams() 转为格式化 JSON 文本（参数只支持可序列化数据） */
  static paramsJson(): string {
    const raw = router.getParams() as Object | undefined;
    if (raw === undefined) {
      return '(无参数)';
    }
    try {
      return JSON.stringify(raw, null, 2);
    } catch (e) {
      return '(参数无法序列化)';
    }
  }

  /** 读取 router 页面栈快照；读取失败时 chain 返回可展示的提示文本 */
  static stackInfo(): RouterStackInfo {
    const info = new RouterStackInfo();
    try {
      const state = router.getState();
      info.path = RouterPageUtil.fullPath(state.path, state.name);
      info.index = state.index;
      info.length = Number(router.getLength());
      const lines: string[] = [];
      for (let i = 1; i <= info.length; i++) {
        if (i === info.index) {
          // 当前页以 router.getState() 为准：部分系统版本上 getStateByIndex()
          // 在 replaceUrl 之后仍会返回被替换页面的旧 name（例如开屏页）
          lines.push(`${i}. ${RouterPageUtil.fullPath(state.path, state.name)}`);
          continue;
        }
        const item = router.getStateByIndex(i);
        if (item !== undefined) {
          lines.push(`${i}. ${RouterPageUtil.fullPath(item.path, item.name)}`);
        }
      }
      info.chain = lines.join('\n');
    } catch (e) {
      info.chain = '(读取 router 页面栈失败)';
    }
    return info;
  }
}
