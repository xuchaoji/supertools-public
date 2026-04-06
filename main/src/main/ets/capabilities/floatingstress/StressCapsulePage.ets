import { StressCapsule } from "../../components/StressCapsule"


@Entry
@ComponentV2
export struct StressCapsulePage {
  build() {
    Column() {
      StressCapsule()
    }
    .width('100%')
    .height('100%')
    .padding(0)
    .margin(0)
    .backgroundColor(Color.Transparent)
    .justifyContent(FlexAlign.Center)
  }
}