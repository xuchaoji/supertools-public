import { SettingSwitchItemCard } from "./SettingSwitchItemCard";

@ComponentV2
export struct ListSetting {
  @Param @Require settingModels: Array<SettingItemModel> = new Array<SettingItemModel>();
  @Local vis: Visibility = Visibility.None;

  aboutToAppear(): void {
    this.onSettingModelChange();
  }

  @Monitor('settingModels.length')
  onSettingModelChange() {
    if (this.settingModels.length === 0) {
      this.vis = Visibility.None;
    } else {
      this.vis = Visibility.Visible;
    }
  }

  build() {
    RelativeContainer() {
      List() {
        ForEach(this.settingModels, (item: SettingItemModel) => {
          SettingSwitchItemCard({
            title: item.name,
            isOn: item.isOn,
            onChange: (isOn: boolean) => {
              if (item.onClick) {
                item.onClick(isOn);
              }
            }
          })
        })
      }.alignRules(
        {
          center: {
            anchor: '__container__',
            align: VerticalAlign.Center
          },
          middle: {
            anchor: '__container__',
            align: HorizontalAlign.Center
          }
        }
      )
    }
    .padding({
      left: '16vp',
      right: '16vp'
    })
    .width('auto')
    .height('auto')
    .visibility(this.vis)
  }
}

@ObservedV2
export class SettingItemModel {
  @Trace name: string = '';
  @Trace isOn: boolean = false;
  onClick: SwitchCardClickAction = (isOn: boolean) => {
  };
}

export type SwitchCardClickAction = (isOn: boolean) => void;