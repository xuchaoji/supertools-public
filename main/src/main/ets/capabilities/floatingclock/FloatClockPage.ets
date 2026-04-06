import { FloatDragHandler } from '../../utils/FloatDragHandler';

@Entry
@Component
struct FloatClockPage {
  @State timeStr: string = "00:00:00.000";
  private intervalId: number = -1;
  private dragHandler: FloatDragHandler = new FloatDragHandler('HyperEntropy_Float_Clock');

  aboutToAppear() {
    this.intervalId = setInterval(() => {
      const date = new Date();
      const h = ('0' + date.getHours()).slice(-2);
      const m = ('0' + date.getMinutes()).slice(-2);
      const s = ('0' + date.getSeconds()).slice(-2);
      const ms = ('00' + date.getMilliseconds()).slice(-3);
      this.timeStr = `${h}:${m}:${s}.${ms}`;
    }, 16);
  }

  aboutToDisappear() {
    if (this.intervalId !== -1) clearInterval(this.intervalId);
  }

  build() {
    Stack() {
      Column() {
        Text(this.timeStr)
          .fontColor('#ccffff00')
          .fontSize(16)
          .fontWeight(FontWeight.Normal)
          .fontFamily('Monospace')
          .textAlign(TextAlign.Center)
          .textShadow({ radius: 2, color: '#FF000000', offsetX: 1, offsetY: 1 })
          .hitTestBehavior(HitTestMode.None)
      }
      .borderRadius(8)
      .padding({left: 2, right: 2})
      .backdropBlur(4)
    }
    .backgroundColor(Color.Transparent)
    .width('100%')
    .height('100%')
    .onTouch((event: TouchEvent) => {
      this.dragHandler.handleTouch(event);
    })
  }
}