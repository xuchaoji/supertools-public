import { PreferencesUtil } from '@pura/harmony-utils';
import { JSON } from '@kit.ArkTS';

const TAG: string = 'UrlHistoryUtil';

/** 历史记录条数上限（与 QrCodePage 一致） */
export const LINK_HISTORY_LIMIT: number = 30;

/** 历史记录项：text = 规范化链接，ts = 记录时间戳 */
export interface LinkHistoryItem {
  text: string;
  ts: number;
}

/**
 * URL 类工具（H5 页面打开 / App Linking 解析）共享的历史记录存取：
 * Preferences 中存 JSON 数组（最新在前），读写统一入口，两个页面共用同一套规则。
 */
export class LinkHistoryUtil {
  /** 读取历史（异常/空返回空数组） */
  static load(key: string): LinkHistoryItem[] {
    try {
      const raw: string = PreferencesUtil.getStringSync(key, '');
      if (!raw) {
        return [];
      }
      const list: LinkHistoryItem[] = JSON.parse(raw) as LinkHistoryItem[];
      return Array.isArray(list) ? list : [];
    } catch (e) {
      console.error(`[${TAG}] load ${key} failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  /** 持久化历史 */
  static persist(key: string, list: LinkHistoryItem[]): void {
    try {
      PreferencesUtil.putSync(key, JSON.stringify(list));
    } catch (e) {
      console.error(`[${TAG}] persist ${key} failed: ${JSON.stringify(e)}`);
    }
  }

  /** 追加一条（去重 + 最新在前 + 截断上限），返回新数组 */
  static add(list: LinkHistoryItem[], text: string): LinkHistoryItem[] {
    const target: string = text.trim();
    if (target.length === 0) {
      return list;
    }
    const next: LinkHistoryItem[] = [];
    next.push({ text: target, ts: Date.now() });
    for (const item of list) {
      if (item.text !== target) {
        next.push(item);
      }
    }
    return next.length > LINK_HISTORY_LIMIT ? next.slice(0, LINK_HISTORY_LIMIT) : next;
  }

  /** 删除某条，返回新数组 */
  static remove(list: LinkHistoryItem[], index: number): LinkHistoryItem[] {
    if (index < 0 || index >= list.length) {
      return list;
    }
    const next: LinkHistoryItem[] = list.slice();
    next.splice(index, 1);
    return next;
  }

  /** 时间显示：当天 HH:MM，跨天 MM-DD HH:MM */
  static formatTime(ts: number): string {
    const d: Date = new Date(ts);
    const now: Date = new Date();
    const pad = (n: number): string => (n < 10 ? '0' + n.toString() : n.toString());
    const hm: string = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    const sameDay: boolean = d.getFullYear() === now.getFullYear() &&
      d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
    if (sameDay) {
      return hm;
    }
    return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${hm}`;
  }
}
