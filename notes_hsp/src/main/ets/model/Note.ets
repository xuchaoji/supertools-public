/**
 * Markdown 笔记的数据模型与纯函数工具。
 *
 * 这一层不依赖 UI，也不依赖宿主 HAP；HSP 内部和宿主都只通过 NotesSdk 访问。
 */

export class Note {
  id: string = '';
  title: string = '';
  content: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class NoteMeta {
  id: string = '';
  title: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
  chars: number = 0;
  snippet: string = '';
}

/** 字数统计：按非空白字符数计算，中文/英文/emoji 都算一个字符。 */
export function countChars(content: string): number {
  return content.replace(/\s/g, '').length;
}

/** 去掉常见 Markdown 标记，生成列表卡片摘要。 */
export function makeSnippet(content: string, maxLength: number = 120): string {
  let text: string = content;
  text = text.replace(/```[\s\S]*?```/g, ' ');
  text = text.replace(/!\[[^\]]*\]\([^)]*\)/g, ' ');
  text = text.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
  text = text.replace(/^#{1,6}\s+/gm, '');
  text = text.replace(/^>\s?/gm, '');
  text = text.replace(/^[-*+]\s+/gm, '');
  text = text.replace(/^\d+\.\s+/gm, '');
  text = text.replace(/[*_`~]/g, '');
  text = text.replace(/<[^>]+>/g, ' ');
  text = text.replace(/\s+/g, ' ').trim();
  if (text.length > maxLength) {
    return text.substring(0, maxLength) + '…';
  }
  return text;
}

/** 从正文推导标题：优先一级标题，其次第一行可读文本。 */
export function deriveTitle(content: string): string {
  const lines: string[] = content.split(/\r?\n/);
  for (const line of lines) {
    const text: string = line.trim();
    if (text.startsWith('# ')) {
      const title: string = text.substring(2).trim();
      if (title.length > 0) {
        return title.substring(0, 40);
      }
    }
  }
  for (const line of lines) {
    const text: string = line.trim();
    if (text.length === 0 || text.startsWith('```')) {
      continue;
    }
    const plain: string = makeSnippet(text, 30);
    if (plain.length > 0) {
      return plain;
    }
  }
  return '未命名笔记';
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 列表里的相对时间，足够轻量，不引入额外依赖。 */
export function formatTime(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const now: number = Date.now();
  const diff: number = now - timestamp;
  if (diff < 60 * 1000) {
    return '刚刚';
  }
  if (diff < 60 * 60 * 1000) {
    return `${Math.floor(diff / (60 * 1000))} 分钟前`;
  }
  const date: Date = new Date(timestamp);
  const today: Date = new Date(now);
  const sameDay: boolean = date.getFullYear() === today.getFullYear() &&
    date.getMonth() === today.getMonth() && date.getDate() === today.getDate();
  if (sameDay) {
    return `今天 ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }
  const yesterday: Date = new Date(now - 24 * 60 * 60 * 1000);
  const isYesterday: boolean = date.getFullYear() === yesterday.getFullYear() &&
    date.getMonth() === yesterday.getMonth() && date.getDate() === yesterday.getDate();
  if (isYesterday) {
    return `昨天 ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }
  if (date.getFullYear() === today.getFullYear()) {
    return `${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

/** 首次打开时展示的示例笔记，同时作为渲染能力的自检素材。 */
export const WELCOME_MARKDOWN: string = [
  '# 欢迎使用 Markdown 笔记',
  '',
  '这是一个 Markdown 笔记功能：编辑、预览、搜索与本地保存。笔记正文保存在应用沙箱。',
  '',
  '## 支持的能力',
  '- 标题、段落、列表、引用',
  '- **粗体**、*斜体*、`行内代码`',
  '- [x] 任务列表',
  '- LaTeX 公式：$E = mc^2$',
  '',
  '> 点击右上角的「预览」查看渲染效果。',
  '',
  '### 代码块',
  '```ts',
  "const hello = 'Markdown';",
  'console.log(hello);',
  '```',
  '',
  '### 表格',
  '| 能力 | 说明 |',
  '| --- | --- |',
  '| 编辑 | 原生 Markdown 编辑器 |',
  '| 预览 | 实时渲染 |',
  '| 存储 | 应用沙箱文件 |',
  '',
  '### 任务列表',
  '- [x] 创建第一篇笔记',
  '- [ ] 试试编辑与预览',
  '- [ ] 再写一篇',
  ''
].join('\n');
