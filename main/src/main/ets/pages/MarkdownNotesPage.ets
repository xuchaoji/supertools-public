import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { NotesFeature } from 'notes_hsp';
import { PageNames } from '../constant/PageNames';
import { WallpaperHost } from '../components/WallpaperHost';
import { SafeArea } from '../utils/SafeArea';
import { LightSense } from '../utils/LightSense';

/**
 * Markdown 笔记的宿主壳。
 *
 * 这里刻意只做三件事：注册 HMRouter 路由、保留壁纸背景、把底部安全区传给 HSP。
 * 列表/编辑器/预览/存储全部在 notes_hsp 中，后续替换 Markdown SDK 不需要改宿主。
 */
@HMRouter({ pageUrl: PageNames.MARKDOWN_NOTES_PAGE })
@ComponentV2
export struct MarkdownNotesPage {
  @Local safeBottom: string = '0px';
  /** 宿主全局光感档位：HSP 不能 import HAP 的 LightSense，由壳显式传入。 */
  @Local lightSense: number = LightSense.LEVEL_EXQUISITE;

  aboutToAppear(): void {
    this.safeBottom = SafeArea.bottom();
    this.lightSense = LightSense.getLevel();
  }

  build() {
    WallpaperHost() {
      NotesFeature({
        safeBottom: this.safeBottom,
        lightSense: this.lightSense,
        onBack: (): void => {
          HMRouterMgr.pop();
        }
      })
    }
  }
}
