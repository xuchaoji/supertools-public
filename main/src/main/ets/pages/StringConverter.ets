import { HMRouter } from '@hadss/hmrouter';
import promptAction from '@ohos.promptAction';
import util from '@ohos.util';
import { ToastUtil } from '@pura/harmony-utils';
import { PageNames } from '../constant/PageNames';

const TAG: string = 'StringConverter'

@HMRouter({pageUrl: PageNames.STR_CONVERT})
@Component
export struct StringConverter {
  @State inputText: string = '';
  @State outputText: string = '';

  // URL编码
  private encodeURL() {
    try {
      this.outputText = encodeURIComponent(this.inputText);
    } catch (error) {
      promptAction.showToast({ message: 'URL编码失败', duration: 2000 });
    }
  }

  // URL解码
  private decodeURL() {
    try {
      this.outputText = decodeURIComponent(this.inputText);
    } catch (error) {
      ToastUtil.showToast('URL解码失败: 无效格式');
    }
  }

  // Base64编码
  private encodeBase64() {
    try {
      // 使用Base64Helper进行编码
      const uint8Array = this.stringToUint8Array(this.inputText);

      this.outputText = this.uint8ArrayToString(new util.Base64Helper().encodeSync(uint8Array));
    } catch (error) {
      ToastUtil.showToast('Base64编码失败');
    }
  }

  // Base64解码
  private decodeBase64() {
    try {
      // 使用Base64Helper进行解码
      const uint8Array = new util.Base64Helper().decodeSync(this.inputText);
      this.outputText = this.uint8ArrayToString(uint8Array);
    } catch (error) {
      ToastUtil.showToast('Base64解码失败: 无效格式');
    }
  }

  // 将字符串转换为Uint8Array
  private stringToUint8Array(str: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encode(str);
  }

  // 将Uint8Array转换为字符串
  private uint8ArrayToString(uint8Array: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decode(uint8Array);
  }

  build() {
    Column({ space: 20 }) {
      // 输入区域
      TextArea({ text: this.inputText, placeholder: '输入要转换的字符串' })
        .height(150)
        .width('95%')
        .fontSize(16)
        .onChange((value: string) => {
          this.inputText = value;
        })

      // 输出区域
      TextArea({ text: this.outputText, placeholder: '转换结果' })
        .height(150)
        .width('95%')
        .fontSize(16)

      // 操作按钮区域
      Grid() {
        GridItem() {
          Button('URL编码')
            .onClick(() => this.encodeURL())
            .height(50)
            .width('90%')
        }

        GridItem() {
          Button('URL解码')
            .onClick(() => this.decodeURL())
            .height(50)
            .width('90%')
        }

        GridItem() {
          Button('Base64编码')
            .onClick(() => this.encodeBase64())
            .height(50)
            .width('90%')
        }

        GridItem() {
          Button('Base64解码')
            .onClick(() => this.decodeBase64())
            .height(50)
            .width('90%')
        }
      }
      .columnsTemplate('1fr 1fr')
      .rowsTemplate('1fr 1fr')
      .height(120)
      .width('95%')
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor($r('sys.color.comp_background_gray'))
  }
}