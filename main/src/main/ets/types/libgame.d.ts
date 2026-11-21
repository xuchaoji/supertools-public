/**
 * libgame.so — 原生 GL 渲染桥（main/src/main/cpp/game/napi_init.cpp）
 *
 * 说明（两处声明的关系）：
 *   - 规范位置是 src/main/cpp/types/libgame/Index.d.ts（hvigor/IDE 的约定）；
 *   - 本文件是同一份声明的镜像，保留是为了兼容仅扫描 ets 源集的检查器。
 *   两份内容必须保持一致；修改接口时请同步。
 *
 * setFrame(frame): 送一帧归一化矩形列表，native 立即绘制到 XComponent Surface。
 *   格式：[count, 0, (x, y, w, h, r, g, b, a, radius, glow) * count]
 * attach(context): 兜底注册入口，context 为 XComponent onLoad 回调参数。
 */
export const setFrame: (frame: Float32Array) => void;
export const attach: (nativeXComponent: object) => void;
/** 取走自上次调用以来的原生触摸事件：[down,dx,dy,move,mx,my,up,0]（坐标已归一化 0..1）。 */
export const pollTouch: () => Float32Array;
/** UI 层矩形：与 setFrame 相同的 [count,0,(x,y,w,h,r,g,b,a,radius,glow)*n] 格式。 */
export const setUiRects: (rects: Float32Array) => void;
/** UI 层文本：texts 与 params 一一对应，params 每项 9 个 float：x,y,size,r,g,b,a,align,bold。 */
export const setUiTexts: (texts: string[], params: Float32Array) => void;
/** 当前 Surface 像素尺寸 [w, h]；未就绪时为 [0,0]。 */
export const getSurfaceSize: () => Float32Array;
