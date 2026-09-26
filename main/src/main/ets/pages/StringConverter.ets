import { HMRouter } from '@hadss/hmrouter';
import util from '@ohos.util';
import { mediaquery } from '@kit.ArkUI';
import { PageNames } from '../constant/PageNames';
import { WallpaperHost } from '../components/WallpaperHost';
import { PageHeader } from '../components/PageHeader';
import { GlassCard } from '../components/GlassCard';
import { GlassButton } from '../components/GlassButton';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';
import { SafeArea } from '../utils/SafeArea';
import { Toast } from '../utils/Toast';

@HMRouter({ pageUrl: PageNames.STR_CONVERT })
@ComponentV2
export struct StringConverter {
  @Local inputText: string = '';
  @Local outputText: string = '';
  /** 沉浸光感：跟随系统深/浅色模式（驱动文字可读性阴影） */
  @Local isDark: boolean = false;
  /** 页面出现时缓存底部安全区，避免 build 中同步查询窗口服务 */
  @Local safeBottom: string = '0px';
  private themeMq: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.safeBottom = SafeArea.bottom();
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(display-mode: dark)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      this.isDark = false;
    }
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
  }

  // ===================== 转换逻辑 =====================

  /** URL 编码 */
  private encodeURL(): void {
    try {
      this.outputText = encodeURIComponent(this.inputText);
    } catch (error) {
      Toast.show('URL 编码失败');
    }
  }

  /** URL 解码 */
  private decodeURL(): void {
    try {
      this.outputText = decodeURIComponent(this.inputText);
    } catch (error) {
      Toast.show('URL 解码失败：无效格式');
    }
  }

  /** Base64 编码 */
  private encodeBase64(): void {
    try {
      const uint8Array = this.stringToUint8Array(this.inputText);
      this.outputText = this.uint8ArrayToString(new util.Base64Helper().encodeSync(uint8Array));
    } catch (error) {
      Toast.show('Base64 编码失败');
    }
  }

  /** Base64 解码 */
  private decodeBase64(): void {
    try {
      const uint8Array = new util.Base64Helper().decodeSync(this.inputText);
      this.outputText = this.uint8ArrayToString(uint8Array);
    } catch (error) {
      Toast.show('Base64 解码失败：无效格式');
    }
  }

  private stringToUint8Array(str: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encode(str);
  }

  private uint8ArrayToString(uint8Array: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decode(uint8Array);
  }

  // ===================== UI =====================

  build() {
    // 全局壁纸宿主：字符串转换页继承主页壁纸背景
    WallpaperHost() {
      Scroll() {
        Column({ space: 12 }) {
          // ---------- 标题栏 ----------
          PageHeader({ title: '字符串转换', subtitle: 'Base64、URL 编解码' })

          // ---------- 输入卡片 ----------
          GlassCard() {
            Column({ space: 10 }) {
              Text('输入内容')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .textShadow(ImmersiveStyles.textShadow(this.isDark))

              TextArea({ text: this.inputText, placeholder: '输入要转换的字符串…' })
                .height(120)
                .width('100%')
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .placeholderFont({ size: 13 })
                .placeholderColor($r('sys.color.font_secondary'))
                .backgroundColor(ImmersiveStyles.inputBg()).backdropBlur(ImmersiveStyles.inputBlur())
                .borderRadius(10)
                .padding(10)
                .onChange((value: string) => {
                  this.inputText = value;
                })

              GlassButton({
                label: '清空',
                fillWidth: true,
                onAction: () => {
                  this.inputText = '';
                  this.outputText = '';
                }
              })
                .width('100%')
            }
            .width('100%')
            .padding(12)
          }

          // ---------- 操作卡片 ----------
          GlassCard() {
            Column({ space: 10 }) {
              Text('转换操作')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .textShadow(ImmersiveStyles.textShadow(this.isDark))

              // 两行两列，按钮用**百分比宽度**定宽。
              // ⚠️ 这里不能用 layoutWeight(1)：实测该卡片宽度是内容驱动的（806px vs 兄弟卡片 988px），
              // 在宽度不确定的父容器里等分权重会算歪（442/300）并被卡片裁掉右侧；
              // 百分比宽度会按可用宽度解析（与同页「清空」按钮 width('100%') 拿到 908 同理）。
              Row() {
                GlassButton({
                  label: 'URL 编码',
                  fillWidth: true,
                  bgColor: $r('sys.color.comp_background_emphasize'),
                  textColor: $r('sys.color.font_on_primary'),
                  strokeWidth: 0,
                  fontWeight: FontWeight.Medium,
                  onAction: () => { this.encodeURL(); }
                })
                  .width('48%')

                GlassButton({
                  label: 'URL 解码',
                  fillWidth: true,
                  onAction: () => { this.decodeURL(); }
                })
                  .width('48%')
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)

              Row() {
                GlassButton({
                  label: 'Base64 编码',
                  fillWidth: true,
                  bgColor: $r('sys.color.comp_background_emphasize'),
                  textColor: $r('sys.color.font_on_primary'),
                  strokeWidth: 0,
                  fontWeight: FontWeight.Medium,
                  onAction: () => { this.encodeBase64(); }
                })
                  .width('48%')

                GlassButton({
                  label: 'Base64 解码',
                  fillWidth: true,
                  onAction: () => { this.decodeBase64(); }
                })
                  .width('48%')
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
            }
            .width('100%')
            .padding(12)
          }

          // ---------- 输出卡片 ----------
          GlassCard() {
            Column({ space: 10 }) {
              Row() {
                Text('转换结果')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('sys.color.font_primary'))
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                Blank()
                Text(`${this.outputText.length}`)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
                  .fontFamily('monospace')
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
              }
              .width('100%')

              TextArea({ text: this.outputText, placeholder: '转换结果' })
                .height(120)
                .width('100%')
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .placeholderFont({ size: 13 })
                .placeholderColor($r('sys.color.font_secondary'))
                .backgroundColor(ImmersiveStyles.inputBg()).backdropBlur(ImmersiveStyles.inputBlur())
                .borderRadius(10)
                .padding(10)
            }
            .width('100%')
            .padding(12)
          }

          // 底部留白（与卡片间距一致）
          Row()
            .height(8)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        // [Pad 大屏适配] 限制最大宽度
        .constraintSize({ maxWidth: 800 })
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .height('100%')
      // 内容不足一屏时 Scroll 默认垂直居中，改为顶部对齐
      .align(Alignment.Top)
      // 滚动到末尾时最后一张卡片会贴到屏幕底部，避让系统手势条
      .padding({ bottom: this.safeBottom })
    }
  }
}
