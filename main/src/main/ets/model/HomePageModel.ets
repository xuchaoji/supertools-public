/**
 * 拖拽场景渲染卡片
 */
@ObservedV2
export class DragCardModel {
  toolCardItem: ToolCardItem = new ToolCardItem();
  public width: Resource | number;
  public height: Resource | number;

  constructor(toolCardItem: ToolCardItem = new ToolCardItem(), width: Resource | number = 0, height: Resource | number = 0) {
    this.toolCardItem = toolCardItem;
    this.width = width;
    this.height = height;
  }
}



@ObservedV2
export class ToolCardItem {
  @Trace name: string | Resource = '';
  @Trace desc: string | Resource = '';
  @Trace icon: string | Resource = '';
  onClick: ToolClickAction = (event: ClickEvent) => {};
}

export type ToolClickAction = (event: ClickEvent) => void;

@ObservedV2
export class ToolCardModel {

}