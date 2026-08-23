# 全局光感效果切换方案（沉浸光感）

> 状态：方案设计稿
> 日期：2026-08-23
> 背景：Tab 栏已用官方 HDS 沉浸材质（IMMERSIVE + EXQUISITE）；本方案把"光感"推广到
> 全局（卡片、背景、反馈、Tab），并提供统一的强弱切换，全部基于官方 API，不自绘模拟。

---

## 一、官方 API 调研结论（非 Tab 组件的光感实现）

### 1. `systemMaterial()` — 通用属性，官方沉浸光感材质（API 26+）

任意组件（卡片/按钮/容器）可挂系统材质：

```ts
import { uiMaterial } from '@kit.ArkUI'; // @ohos.arkui.uiMaterial

Row()
  .systemMaterial(new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.REGULAR, // ULTRA_THIN/THIN/REGULAR/THICK/ULTRA_THICK
    materialColor: Color.Transparent,          // 附加颜色
    colorInvert: false,                        // 子内容自动反色
    applyShadow: true,                         // 材质阴影
    interactive: false,                        // 是否响应手势
    lightEffect: { color: Color.White },       // 光效交互反馈（光感跟随手势）
  }))
```

- 官方文档说明：**高算力设备在系统材质层加滤镜（玻璃感）；低算力设备自动降级为
  backgroundColor/border/shadow**。`undefined` 表示还原为无系统材质。
- `uiMaterial.getMaterialInfo()` 可查询设备当前材质配置（state/type），用于能力探测。

### 2. `backgroundBlurStyle(BlurStyle)` — 系统毛玻璃（API 10+，全版本可用）

```ts
Row()
  .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, { colorMode: ThemeColorMode.SYSTEM })
```
BlurStyle 档位：`Thin / Regular / Thick / ComponentThick / UltraThick`；可配
`adaptiveColor`（背景自适应反色）与 `scale`。当前应用卡片已使用该方案
（ImmersiveStyles.cardBase + COMPONENT_THICK），是兼容性最好的基础光感。

### 3. `hdsEffect.HdsEffectBuilder` + `.visualEffect()` — HDS 官方视觉特效（API 20+）

```ts
import { hdsEffect } from '@kit.UIDesignKit';

const effect = new hdsEffect.HdsEffectBuilder()
  .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)   // 按压阴影反馈
  .pointLight({                                            // 点光源光感（真正的"光"）
    sourceType: hdsEffect.PointLightSourceType.BRIGHT,     // SOFT=柔和 / BRIGHT=明亮
    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT, // 照亮边框/内容
    options: { color: '#FFFFFF', intensity: 0.8, height: 40, bloom: 0.6 },
  })
  .buildEffect();

Row().visualEffect(effect);   // 通用属性挂载
```

- `pointLight` 是最贴合"光感"的官方能力：光源照亮组件边缘/内容，强度/高度/泛光可调。
- `shaderEffect` 提供流光动画（双边缘流光 / UV 背景流光），HdsVisualComponent 提供
  场景化流光组件（HdsSceneController 播放/暂停/停止）——适合强调效果，非默认项。

### 4. `hdsMaterial` — HDS 组件（Tab 栏等）内部材质

`MaterialType`（NONE/ADAPTIVE/IMMERSIVE）+ `MaterialLevel`
（EXQUISITE=精致 / GENTLE=柔和 / SMOOTH=顺滑 / ADAPTIVE=跟随系统）。
Tab 栏已配置 `IMMERSIVE + EXQUISITE`。`getSystemMaterialTypes()` 可查询设备支持的材质类型。

### 5. 小结：官方能力矩阵

| 能力 | API | 作用面 | 说明 |
|---|---|---|---|
| `systemMaterial` | 26+ | 任意组件 | 官方沉浸材质，含光效反馈，低算力自动降级 |
| `backgroundBlurStyle` | 10+ | 任意组件 | 毛玻璃，全版本可用 |
| `pointLight`/`pressShadow`/`shaderEffect` | 20+ | 任意组件 | 官方视觉特效（点光源/按压/流光）|
| `hdsMaterial` | 23+ | HDS 组件 | Tab 栏等内部材质 |
| `HdsVisualComponent` | 20+ | 独立组件 | 场景流光动画 |

---

## 二、全局光感档位设计

档位（持久化 `light_sense`：0~3），全局生效、逐表面映射：

| 档位 | 名称 | 定位 |
|---|---|---|
| 0 | 关闭 | 纯色背景，无毛玻璃/无光效（省电、最朴素）|
| 1 | 柔和 | 薄毛玻璃 + 无点光源（当前默认观感）|
| 2 | 标准 | 厚毛玻璃 + 柔和点光源 + Tab SMOOTH |
| 3 | 精致 | 官方沉浸材质 + 明亮点光源 + Tab EXQUISITE（默认推荐）|

### 逐表面映射表

| 表面 | 关闭(0) | 柔和(1) | 标准(2) | 精致(3) |
|---|---|---|---|---|
| 卡片/分组背景 | 纯色 `cardBase(0%)` | `backgroundBlurStyle(Thin)` + 低透明 | `backgroundBlurStyle(ComponentThick)` | `systemMaterial(REGULAR)` |
| 卡片光效反馈 | 无 | `hoverEffect(Scale)` | `pointLight(SOFT, intensity 0.4)` | `pointLight(BRIGHT, intensity 0.8)` + `lightEffect` |
| Tab 栏材质 | 无（纯色胶囊） | `GENTLE` | `SMOOTH` | `EXQUISITE` |
| 壁纸模糊等级 | 0 | 30 | 50 | 70 |
| 全局底色 | 纯灰 | 微透明白 | 透明白 + 模糊 | 系统材质透出 |

---

## 三、兼容性策略

```
deviceInfo.distributionOSApiVersion
├─ ≥ 26（HarmonyOS 7.0，当前设备）：systemMaterial / uiMaterial / pointLight 全量可用
├─ 23~25（HarmonyOS 6.x）：HdsTabs 可用；systemMaterial 不可用 → 回退 backgroundBlurStyle
└─ < 23：legacy 手绘悬浮 Tab + backgroundBlurStyle（现状兜底）
```

能力探测（运行期）：
```ts
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

const api = deviceInfo.distributionOSApiVersion;
const supportSystemMaterial = api >= 260000;                 // API 26
const supportHds = api >= 230000;                            // HdsTabs
// 可选：const info = uiMaterial.getMaterialInfo();           // 设备是否启用沉浸材质
```

---

## 四、实现方案

### 4.1 数据层
- `SpKeys.LIGHT_SENSE = 'light_sense'`（0~3，默认 3）
- `LightSense` 工具类（`utils/LightSense.ets`）：
  - `getLevel()` / `setLevel(v)`（持久化 + `AppStorage.setOrCreate('LightSense', v)`）
  - `cardBg(level, isDark)` → 卡片背景色（各档透明度）
  - `cardBlurStyle(level)` → `BlurStyle | undefined`（undefined=纯色）
  - `useSystemMaterial(level)` → `boolean`（>=2 且支持 API 26）
  - `immersiveMaterial(level)` → `uiMaterial.ImmersiveMaterial | undefined`
  - `tabMaterialLevel(level)` → `hdsMaterial.MaterialLevel`
  - `pointLightEffect(level)` → `hdsEffect.PointLightEffect | undefined`

### 4.2 UI 层（逐表面接入）
1. **设置页**：「主页背景」区块下新增「光感」分段选择（关闭/柔和/标准/精致），
   变更即持久化 + AppStorage 广播。
2. **ImmersiveStyles / SettingGroup / 工具页卡片**：背景色与模糊按档位取值；
   API 26 设备在档位 ≥2 时改挂 `systemMaterial`（替换自绘毛玻璃）。
3. **Tab 栏**：`hdsTabsModifier.systemMaterialEffect.materialLevel` 按档位
   （0→NONE 关闭 / 1→GENTLE / 2→SMOOTH / 3→EXQUISITE）。
4. **卡片按压反馈**：档位 ≥2 时给主卡片挂 `hdsEffect.HdsEffectBuilder().pointLight(...)`
   的 `visualEffect`（`BlurStrategy.ADAPTIVE` 控制开关）。
5. **壁纸模糊**：`WallpaperUtil.blurRadius` 与档位联动（或保留独立滑杆，二者取其一）。

### 4.3 性能与降级
- 档位 0 关闭所有模糊/材质 → 最省电。
- 低算力设备 `systemMaterial` 自动降级为边框/阴影（官方行为），无需额外处理；
  API < 26 直接走 `backgroundBlurStyle` 分支。
- 光效（pointLight/lightEffect）只在档位 ≥2 且 API ≥ 20 时挂载，避免低端机卡顿。

---

## 五、涉及文件

| 文件 | 改动 |
|---|---|
| `constant/SpKeys.ets` | +`LIGHT_SENSE` |
| `utils/LightSense.ets` | 新增：档位工具类（映射/探测/持久化）|
| `pages/HomePage.ets` | Tab 材质级别按档位；设置页加光感选择 |
| `utils/ImmersiveStyles.ets` | 卡片参数改由档位驱动 |
| `components/SettingGroup.ets` | 背景按档位（systemMaterial/毛玻璃/纯色）|
| `components/WallpaperHost.ets` | 背景同 SettingGroup |
| 各工具页卡片 | 统一走 `LightSense.cardBg/cardBlurStyle` |

## 六、验证点
1. 四档切换即时生效（无需重启）。
2. 深/浅色模式下毛玻璃不发灰/发白。
3. API 26 设备出现官方玻璃滤镜与光效反馈；API < 26 回退毛玻璃无崩溃。
4. 档位 0 下无模糊/材质，滑动列表不卡顿。
5. 重启后档位保持。
