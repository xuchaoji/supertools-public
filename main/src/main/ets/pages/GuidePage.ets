import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import { PreferencesUtil } from "@pura/harmony-utils";
import { PageNames } from "../constant/PageNames";
import { SpKeys } from "../constant/SpKeys";

@HMRouter({pageUrl: PageNames.GUIDE_PAGE})
@ComponentV2
export struct GuidePage {
  aboutToAppear(): void {
    let privacyAgreed = PreferencesUtil.getBooleanSync(SpKeys.PRIVACY_AGREE, false);
    if (privacyAgreed) {
      HMRouterMgr.replace({pageUrl: PageNames.HOME_PAGE});
    } else {
      HMRouterMgr.replace({pageUrl: PageNames.PRIVACY_PAGE});
    }
  }
  build() {
  }
}