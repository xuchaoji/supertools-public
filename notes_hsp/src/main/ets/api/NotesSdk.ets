/**
 * notes_hsp 对外 API。
 *
 * 宿主（HAP）只依赖这里和 NotesFeature 组件；仓库实现、文件格式、
 * Markdown 渲染库都封装在 HSP 内部，后续替换渲染器不影响宿主。
 */

import { common } from '@kit.AbilityKit';
import { NotesRepository } from '../data/NotesRepository';
import { Note, NoteMeta } from '../model/Note';

export class NotesSdk {
  public static readonly VERSION: string = '1.0.0';

  /** 幂等初始化；重复调用直接返回。 */
  public static init(context: common.UIAbilityContext): void {
    NotesRepository.getInstance().init(context);
  }

  public static isReady(): boolean {
    return NotesRepository.getInstance().isReady();
  }

  public static list(): NoteMeta[] {
    return NotesRepository.getInstance().list();
  }

  public static createDraft(): Note {
    return NotesRepository.getInstance().createDraft();
  }

  public static load(id: string): Note | null {
    return NotesRepository.getInstance().load(id);
  }

  public static save(note: Note): Note {
    return NotesRepository.getInstance().save(note);
  }

  public static delete(id: string): void {
    NotesRepository.getInstance().delete(id);
  }

  public static version(): string {
    return NotesSdk.VERSION;
  }
}
