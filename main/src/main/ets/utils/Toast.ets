import { AppUtil } from '@pura/harmony-utils';

/**
 * 全局轻提示（Toast）唯一出口。
 *
 * 背景：项目历史上混用两种实现 —— 全局 `promptAction.showToast({...})`（绝大多数页面）
 * 与 `@pura/harmony-utils` 的 `ToastUtil.showToast('...')`（StringConverter / RecordCard /
 * ScreenRecordPage），两者在时长、位置与后续可替换性上都不一致，属于风格分裂。
 *
 * 现统一到此处：
 * - **新代码一律 `Toast.show('...')`，不要再直接调 promptAction / ToastUtil**；
 * - 走 API 12 推荐的 `UIContext.getPromptAction()`（全局 `promptAction.showToast` 已废弃），
 *   因此这里也是将来替换提示实现时**唯一**需要改的地方。
 *
 * 用法：
 *   Toast.show('URL 解码失败：无效格式');
 *   Toast.show('已复制', 1500);   // 自定义时长（ms）
 */
export class Toast {
  private static readonly DEFAULT_DURATION: number = 2000;

  /** 显示轻提示；失败只记日志，不影响主流程 */
  static show(message: string, duration: number = Toast.DEFAULT_DURATION): void {
    try {
      AppUtil.getUIContext().getPromptAction().showToast({ message: message, duration: duration });
    } catch (e) {
      // UIContext 未就绪（非 UI 上下文调用）时只记日志，避免打断主流程
      console.error(`[Toast] showToast failed: ${JSON.stringify(e)}`);
    }
  }
}
