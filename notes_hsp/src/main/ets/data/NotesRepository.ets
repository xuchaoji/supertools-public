/**
 * 笔记仓库：应用沙箱内的纯文件存储，不依赖宿主 HAP、AppStorage 或 Preferences。
 *
 * 目录结构：
 *   <filesDir>/markdown_notes/
 *     index.json        元数据数组（标题、时间、字数、摘要）
 *     <noteId>.md       正文（原始 Markdown）
 *     .seeded           首次示例是否已写入
 *
 * 之所以用文件而不是 Preferences：Markdown 正文可能很长，文件写入/读取更稳，
 * 也方便后续做导入导出、附件、全文检索。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Note, NoteMeta, WELCOME_MARKDOWN, countChars, deriveTitle, makeSnippet } from '../model/Note';

const TAG: string = 'NotesRepository';
const ROOT_DIR_NAME: string = 'markdown_notes';
const INDEX_FILE: string = 'index.json';
const SEED_MARKER: string = '.seeded';
const MAX_TITLE_LENGTH: number = 60;

interface NoteIndexEntry {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  chars: number;
  snippet: string;
}

export class NotesRepository {
  private static instance: NotesRepository | null = null;

  private rootDir: string = '';
  private indexFile: string = '';
  private seedMarker: string = '';
  private metas: NoteMeta[] = [];
  private ready: boolean = false;

  public static getInstance(): NotesRepository {
    if (NotesRepository.instance === null) {
      NotesRepository.instance = new NotesRepository();
    }
    return NotesRepository.instance;
  }

  public init(context: common.UIAbilityContext): void {
    if (this.ready) {
      return;
    }
    this.rootDir = `${context.filesDir}/${ROOT_DIR_NAME}`;
    this.indexFile = `${this.rootDir}/${INDEX_FILE}`;
    this.seedMarker = `${this.rootDir}/${SEED_MARKER}`;
    this.ensureDir();
    this.loadIndex();
    if (this.metas.length === 0) {
      this.rebuildFromFiles();
    }
    // 先置 ready：seedIfEmpty 内部会走公开的 save()，而 save() 会做 ensureReady 校验。
    this.ready = true;
    this.migrateLegacySeed();
    this.seedIfEmpty();
    console.info(`${TAG} initialized, notes=${this.metas.length}, root=${this.rootDir}`);
  }

  public isReady(): boolean {
    return this.ready;
  }

  public list(): NoteMeta[] {
    this.ensureReady();
    const copy: NoteMeta[] = this.metas.slice();
    copy.sort((a: NoteMeta, b: NoteMeta) => b.updatedAt - a.updatedAt);
    return copy;
  }

  public createDraft(): Note {
    const now: number = Date.now();
    const note: Note = new Note();
    note.id = NotesRepository.newId();
    note.title = '';
    note.content = '';
    note.createdAt = now;
    note.updatedAt = now;
    return note;
  }

  public load(id: string): Note | null {
    this.ensureReady();
    const path: string = this.notePath(id);
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      const content: string = fs.readTextSync(path);
      const note: Note = new Note();
      note.id = id;
      note.content = content;
      note.createdAt = this.metaCreatedAt(id);
      note.updatedAt = this.metaUpdatedAt(id);
      note.title = this.metaTitle(id);
      if (note.title.length === 0) {
        note.title = deriveTitle(content);
      }
      return note;
    } catch (e) {
      console.error(`${TAG} load failed id=${id}: ${JSON.stringify(e)}`);
      return null;
    }
  }

  public save(note: Note): Note {
    this.ensureReady();
    if (note.id.length === 0) {
      note.id = NotesRepository.newId();
    }
    const now: number = Date.now();
    const title: string = note.title.trim().length > 0 ? note.title.trim() : deriveTitle(note.content);
    note.title = title.substring(0, MAX_TITLE_LENGTH);
    note.updatedAt = now;
    if (note.createdAt <= 0) {
      note.createdAt = now;
    }
    this.writeText(this.notePath(note.id), note.content);

    const meta: NoteMeta = new NoteMeta();
    meta.id = note.id;
    meta.title = note.title;
    meta.createdAt = note.createdAt;
    meta.updatedAt = note.updatedAt;
    meta.chars = countChars(note.content);
    meta.snippet = makeSnippet(note.content);
    this.upsertMeta(meta);
    this.writeIndex();
    return note;
  }

  public delete(id: string): void {
    this.ensureReady();
    try {
      const path: string = this.notePath(id);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.error(`${TAG} delete file failed id=${id}: ${JSON.stringify(e)}`);
    }
    this.metas = this.metas.filter((item: NoteMeta) => item.id !== id);
    this.writeIndex();
  }

  private ensureReady(): void {
    if (!this.ready) {
      throw new Error('NotesRepository is not initialized');
    }
  }

  private ensureDir(): void {
    if (!fs.accessSync(this.rootDir)) {
      fs.mkdirSync(this.rootDir, true);
    }
  }

  private notePath(id: string): string {
    return `${this.rootDir}/${id}.md`;
  }

  private loadIndex(): void {
    if (!fs.accessSync(this.indexFile)) {
      this.metas = [];
      return;
    }
    try {
      const raw: string = fs.readTextSync(this.indexFile);
      const parsed: NoteIndexEntry[] = JSON.parse(raw) as NoteIndexEntry[];
      const loaded: NoteMeta[] = [];
      for (const entry of parsed) {
        if (entry.id === undefined || entry.id === null || entry.id.length === 0) {
          continue;
        }
        const meta: NoteMeta = new NoteMeta();
        meta.id = entry.id;
        meta.title = entry.title ?? '';
        meta.createdAt = entry.createdAt ?? 0;
        meta.updatedAt = entry.updatedAt ?? 0;
        meta.chars = entry.chars ?? 0;
        meta.snippet = entry.snippet ?? '';
        loaded.push(meta);
      }
      this.metas = loaded;
    } catch (e) {
      console.error(`${TAG} index parse failed: ${JSON.stringify(e)}`);
      this.metas = [];
    }
  }

  /** index.json 丢失/损坏时，从 .md 文件恢复元数据。 */
  private rebuildFromFiles(): void {
    try {
      const names: string[] = fs.listFileSync(this.rootDir);
      const rebuilt: NoteMeta[] = [];
      for (const name of names) {
        if (!name.endsWith('.md')) {
          continue;
        }
        const id: string = name.substring(0, name.length - 3);
        const path: string = `${this.rootDir}/${name}`;
        try {
          const content: string = fs.readTextSync(path);
          const stat = fs.statSync(path);
          const meta: NoteMeta = new NoteMeta();
          meta.id = id;
          meta.title = deriveTitle(content);
          meta.createdAt = stat.mtime * 1000;
          meta.updatedAt = stat.mtime * 1000;
          meta.chars = countChars(content);
          meta.snippet = makeSnippet(content);
          rebuilt.push(meta);
        } catch (e) {
          console.error(`${TAG} rebuild skip ${name}: ${JSON.stringify(e)}`);
        }
      }
      this.metas = rebuilt;
      if (rebuilt.length > 0) {
        this.writeIndex();
      }
      console.info(`${TAG} rebuilt index from ${rebuilt.length} markdown files`);
    } catch (e) {
      console.error(`${TAG} rebuild failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 旧版本示例笔记的迁移：只替换仍保留旧示例标记的「欢迎使用 Markdown 笔记」，
   * 不碰用户自己写的内容或已改过标题的笔记。
   */
  private migrateLegacySeed(): void {
    const target: NoteMeta | undefined = this.metas.find((item: NoteMeta) =>
      item.title === '欢迎使用 Markdown 笔记');
    if (!target) {
      return;
    }
    try {
      const path: string = this.notePath(target.id);
      if (!fs.accessSync(path)) {
        return;
      }
      const content: string = fs.readTextSync(path);
      const isLegacy: boolean = content.includes('lv-markdown-in') ||
        content.includes('这是运行在 **HSP** 里的 Markdown 笔记功能');
      if (!isLegacy) {
        return;
      }
      const note: Note = new Note();
      note.id = target.id;
      note.title = '欢迎使用 Markdown 笔记';
      note.content = WELCOME_MARKDOWN;
      note.createdAt = target.createdAt;
      this.save(note);
      console.info(`${TAG} legacy welcome note migrated`);
    } catch (e) {
      console.error(`${TAG} migrate legacy seed failed: ${JSON.stringify(e)}`);
    }
  }

  private seedIfEmpty(): void {
    if (this.metas.length > 0) {
      return;
    }
    if (fs.accessSync(this.seedMarker)) {
      return;
    }
    try {
      const note: Note = this.createDraft();
      note.title = '欢迎使用 Markdown 笔记';
      note.content = WELCOME_MARKDOWN;
      this.save(note);
      this.writeText(this.seedMarker, '1');
      console.info(`${TAG} welcome note seeded`);
    } catch (e) {
      console.error(`${TAG} seed failed: ${JSON.stringify(e)}`);
    }
  }

  private upsertMeta(meta: NoteMeta): void {
    const index: number = this.metas.findIndex((item: NoteMeta) => item.id === meta.id);
    if (index >= 0) {
      this.metas[index] = meta;
    } else {
      this.metas.push(meta);
    }
    this.metas.sort((a: NoteMeta, b: NoteMeta) => b.updatedAt - a.updatedAt);
  }

  private writeIndex(): void {
    const tmp: string = `${this.indexFile}.tmp`;
    this.writeText(tmp, JSON.stringify(this.metas));
    try {
      if (fs.accessSync(this.indexFile)) {
        fs.unlinkSync(this.indexFile);
      }
      fs.renameSync(tmp, this.indexFile);
    } catch (e) {
      console.error(`${TAG} write index failed: ${JSON.stringify(e)}`);
      // 兜底：直接写目标文件，至少不让元数据完全丢失
      this.writeText(this.indexFile, JSON.stringify(this.metas));
    }
  }

  private writeText(path: string, text: string): void {
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
  }

  private metaCreatedAt(id: string): number {
    const meta: NoteMeta | undefined = this.metas.find((item: NoteMeta) => item.id === id);
    return meta ? meta.createdAt : 0;
  }

  private metaUpdatedAt(id: string): number {
    const meta: NoteMeta | undefined = this.metas.find((item: NoteMeta) => item.id === id);
    return meta ? meta.updatedAt : 0;
  }

  private metaTitle(id: string): string {
    const meta: NoteMeta | undefined = this.metas.find((item: NoteMeta) => item.id === id);
    return meta ? meta.title : '';
  }

  private static newId(): string {
    return `n_${Date.now().toString(36)}_${Math.floor(Math.random() * 1000000).toString(36)}`;
  }
}
