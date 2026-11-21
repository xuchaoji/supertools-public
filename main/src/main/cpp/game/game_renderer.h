/*
 * game_renderer.h — XComponent Surface 上的原生渲染器。
 *
 * 两层：
 *  1. 棋盘层（GL）：矩形列表，由 ArkTS 每帧推送，负责动画；
 *  2. UI 层（OH_Drawing + 纹理）：HUD、按钮、弹窗、调试面板等所有游戏控件，
 *     由 ArkTS 在 UI 状态变化时推送「矩形 + 文本」显示列表，native 离屏绘制成
 *     一张全屏 RGBA 纹理后叠加到棋盘上。
 *
 * 这样 XComponent 是页面里唯一的 ArkUI 节点，开启“显示布局边界”也看不到
 * HUD/按钮/弹窗——和真实游戏引擎整屏自绘一致。
 *
 * 棋盘帧数据（Float32Array）：
 *   [0] = itemCount, [1] = 保留
 *   每项 10 个 float：x, y, w, h, r, g, b, a, radius, glow（坐标归一化 0..1，y 向下）
 *
 * UI 矩形（Float32Array）沿用同一格式；UI 文本单独传：
 *   texts: string[]；params 每项 9 个 float：
 *   x, y, size, r, g, b, a, align(0左/1中/2右), bold(0/1)
 *   x/y 为归一化坐标（y 为文本顶部），size 为相对 Surface 高度的比例。
 */

#ifndef GAME_RENDERER_H
#define GAME_RENDERER_H

#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <native_drawing/drawing_bitmap.h>
#include <native_drawing/drawing_brush.h>
#include <native_drawing/drawing_canvas.h>
#include <native_drawing/drawing_font_collection.h>
#include <native_drawing/drawing_rect.h>
#include <native_drawing/drawing_round_rect.h>
#include <native_drawing/drawing_text_declaration.h>
#include <native_drawing/drawing_text_typography.h>

class GameRenderer {
public:
    static GameRenderer &GetInstance();

    void AttachXComponent(OH_NativeXComponent *component);
    void SetFrame(const float *data, size_t length);
    void SetUiRects(const float *data, size_t length);
    void SetUiTexts(const std::vector<std::string> &texts, const float *params, size_t paramCount);
    void ReleaseSurface();
    void PollTouch(float *out8);
    /** 当前 Surface 的像素尺寸（宽, 高）；未就绪时为 0。 */
    void GetSurfaceSize(float *out2);

private:
    GameRenderer() = default;
    ~GameRenderer() = default;
    GameRenderer(const GameRenderer &) = delete;
    GameRenderer &operator=(const GameRenderer &) = delete;

    bool EnsureEgl(void *window);
    bool EnsureProgram();
    bool EnsureTextureProgram();
    void ReleaseEgl();
    void ReleaseUi();
    void UploadFrameLocked();
    void DrawLocked();
    void DrawBoardLocked();
    void RenderUiLocked();
    void DrawUiLocked();

    static void OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window);
    static void OnSurfaceChangedCB(OH_NativeXComponent *component, void *window);
    static void OnSurfaceDestroyedCB(OH_NativeXComponent *component, void *window);
    static void DispatchTouchEventCB(OH_NativeXComponent *component, void *window);

    mutable std::mutex mutex_;

    // ---- 棋盘 ----
    std::vector<float> frame_;
    bool hasFrame_ = false;
    bool ready_ = false;
    void *window_ = nullptr;
    int widthPx_ = 0;
    int heightPx_ = 0;

    EGLDisplay eglDisplay_ = EGL_NO_DISPLAY;
    EGLConfig eglConfig_ = nullptr;
    EGLSurface eglSurface_ = EGL_NO_SURFACE;
    EGLContext eglContext_ = EGL_NO_CONTEXT;

    GLuint program_ = 0;
    GLuint vbo_ = 0;
    GLint viewportLoc_ = -1;
    std::vector<float> vertices_;

    // ---- UI 层 ----
    std::vector<float> uiRects_;
    std::vector<std::string> uiTexts_;
    std::vector<float> uiTextParams_;
    bool uiDirty_ = true;

    OH_Drawing_Bitmap *uiBitmap_ = nullptr;
    OH_Drawing_Canvas *uiCanvas_ = nullptr;
    OH_Drawing_FontCollection *fontCollection_ = nullptr;
    GLuint uiTexture_ = 0;
    int uiTexW_ = 0;
    int uiTexH_ = 0;

    GLuint texProgram_ = 0;
    GLuint texVbo_ = 0;
    GLint texViewportLoc_ = -1;
    GLint texSamplerLoc_ = -1;

    OH_NativeXComponent_Callback callback_{};

    // ---- 触摸 ----
    bool touchDown_ = false;
    float touchDownX_ = 0.0f;
    float touchDownY_ = 0.0f;
    bool touchMove_ = false;
    float touchMoveX_ = 0.0f;
    float touchMoveY_ = 0.0f;
    bool touchUp_ = false;
};

#endif // GAME_RENDERER_H
