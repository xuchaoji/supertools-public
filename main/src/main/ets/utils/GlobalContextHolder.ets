import { common } from "@kit.AbilityKit";

export class GlobalContextHolder {
  private static instance: GlobalContextHolder;
  private _uiAbilityContext: common.UIAbilityContext | undefined;

  public set uiAbilityContext(value: common.UIAbilityContext | undefined) {
    this._uiAbilityContext = value;
  }

  public get uiAbilityContext(): common.UIAbilityContext | undefined {
    return this._uiAbilityContext;
  }

  public static getInstance(): GlobalContextHolder {
    if (!GlobalContextHolder.instance) {
      GlobalContextHolder.instance = new GlobalContextHolder();
    }
    return GlobalContextHolder.instance;
  }
}