/**
 * notes_hsp 公共出口。
 *
 * 宿主只从这里取：
 *  - NotesFeature：完整笔记 UI（列表 + 编辑器 + 预览）
 *  - NotesSdk：宿主若需要预初始化/读取版本时使用
 */
export { NotesFeature } from './src/main/ets/ui/NotesFeature';
export { NotesSdk } from './src/main/ets/api/NotesSdk';
export { Note, NoteMeta } from './src/main/ets/model/Note';
