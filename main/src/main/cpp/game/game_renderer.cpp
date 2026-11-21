/*
 * game_renderer.cpp — EGL/GLES2 + OH_Drawing 的双层渲染器。
 *
 * 棋盘用 GL 画（动画每帧刷新），所有游戏 UI 用 OH_Drawing 离屏画成一张
 * 全屏透明纹理，再叠加到棋盘上。UI 只在显示列表变化时重绘，所以中文文本
 * 不需要每帧排版，也不会出现在 ArkUI 布局树里。
 */

#include "game_renderer.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include <hilog/log.h>

namespace {
constexpr uint32_t GAME_LOG_DOMAIN = 0x3200;
constexpr const char *GAME_LOG_TAG = "GameGL";

constexpr int FLOATS_PER_VERTEX = 12;
constexpr int VERTICES_PER_ITEM = 6;
constexpr int FLOATS_PER_ITEM = 10;
constexpr int FLOATS_PER_TEXT = 9;   // x, y, size, r, g, b, a, align, bold

const char *VERTEX_SHADER = R"(
attribute vec2 a_corner;
attribute vec2 a_pos;
attribute vec2 a_size;
attribute vec4 a_color;
attribute float a_radius;
attribute float a_glow;

uniform vec2 u_viewport;

varying vec2 v_uv;
varying vec4 v_color;
varying vec2 v_half;
varying float v_radius;
varying float v_glow;

void main() {
    vec2 px = (a_pos + a_corner * a_size) * u_viewport;
    vec2 ndc = vec2(px.x / u_viewport.x * 2.0 - 1.0,
                    1.0 - px.y / u_viewport.y * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);

    v_uv = a_corner;
    v_color = a_color;
    v_half = a_size * u_viewport * 0.5;
    float shortHalf = min(v_half.x, v_half.y);
    v_radius = min(a_radius * 2.0 * shortHalf, shortHalf);
    v_glow = a_glow;
}
)";

const char *FRAGMENT_SHADER = R"(
precision mediump float;

varying vec2 v_uv;
varying vec4 v_color;
varying vec2 v_half;
varying float v_radius;
varying float v_glow;

void main() {
    vec2 p = (v_uv - 0.5) * 2.0 * v_half;
    vec2 q = abs(p) - (v_half - vec2(v_radius));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - v_radius;
    float alpha = 1.0 - smoothstep(-1.0, 1.0, d);
    if (alpha <= 0.002) {
        discard;
    }
    float shade = 0.88 + 0.20 * (1.0 - v_uv.y);
    vec3 color = v_color.rgb * shade + vec3(v_glow * 0.30);
    gl_FragColor = vec4(color, v_color.a * alpha);
}
)";

const char *TEX_VERTEX_SHADER = R"(
attribute vec2 a_pos;
attribute vec2 a_uv;
uniform vec2 u_viewport;
varying vec2 v_uv;
void main() {
    vec2 px = a_pos * u_viewport;
    vec2 ndc = vec2(px.x / u_viewport.x * 2.0 - 1.0,
                    1.0 - px.y / u_viewport.y * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    v_uv = a_uv;
}
)";

const char *TEX_FRAGMENT_SHADER = R"(
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
void main() {
    gl_FragColor = texture2D(u_tex, v_uv);
}
)";

GLuint CompileShader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    if (shader == 0) {
        return 0;
    }
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled == GL_TRUE) {
        return shader;
    }
    char info[512] = {0};
    glGetShaderInfoLog(shader, sizeof(info) - 1, nullptr, info);
    OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "shader compile failed: %{public}s", info);
    glDeleteShader(shader);
    return 0;
}

GLuint LinkProgram(const char *vsSource, const char *fsSource,
                   const char **attribNames, int attribCount) {
    GLuint vs = CompileShader(GL_VERTEX_SHADER, vsSource);
    if (vs == 0) {
        return 0;
    }
    GLuint fs = CompileShader(GL_FRAGMENT_SHADER, fsSource);
    if (fs == 0) {
        glDeleteShader(vs);
        return 0;
    }
    GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    for (int i = 0; i < attribCount; ++i) {
        glBindAttribLocation(program, i, attribNames[i]);
    }
    glLinkProgram(program);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint linked = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (linked == GL_TRUE) {
        return program;
    }
    char info[512] = {0};
    glGetProgramInfoLog(program, sizeof(info) - 1, nullptr, info);
    OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "program link failed: %{public}s", info);
    glDeleteProgram(program);
    return 0;
}

uint32_t ColorFromFloats(float r, float g, float b, float a) {
    const uint32_t ri = static_cast<uint32_t>(std::clamp(r, 0.0f, 1.0f) * 255.0f + 0.5f);
    const uint32_t gi = static_cast<uint32_t>(std::clamp(g, 0.0f, 1.0f) * 255.0f + 0.5f);
    const uint32_t bi = static_cast<uint32_t>(std::clamp(b, 0.0f, 1.0f) * 255.0f + 0.5f);
    const uint32_t ai = static_cast<uint32_t>(std::clamp(a, 0.0f, 1.0f) * 255.0f + 0.5f);
    return (ai << 24) | (ri << 16) | (gi << 8) | bi;
}

void PushQuad(float *out, size_t &cursor, float x, float y, float w, float h) {
    static const float corners[6][2] = {
        {0.0f, 0.0f}, {1.0f, 0.0f}, {0.0f, 1.0f},
        {1.0f, 0.0f}, {1.0f, 1.0f}, {0.0f, 1.0f}
    };
    for (int i = 0; i < 6; ++i) {
        out[cursor++] = x + corners[i][0] * w;
        out[cursor++] = y + corners[i][1] * h;
        out[cursor++] = corners[i][0];
        out[cursor++] = corners[i][1];
    }
}
} // namespace

GameRenderer &GameRenderer::GetInstance() {
    static GameRenderer instance;
    return instance;
}

void GameRenderer::AttachXComponent(OH_NativeXComponent *component) {
    if (component == nullptr) {
        return;
    }
    callback_.OnSurfaceCreated = OnSurfaceCreatedCB;
    callback_.OnSurfaceChanged = OnSurfaceChangedCB;
    callback_.OnSurfaceDestroyed = OnSurfaceDestroyedCB;
    callback_.DispatchTouchEvent = DispatchTouchEventCB;
    int32_t ret = OH_NativeXComponent_RegisterCallback(component, &callback_);
    OH_LOG_Print(LOG_APP, ret == 0 ? LOG_INFO : LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG,
                 "AttachXComponent ret=%{public}d", ret);
}

void GameRenderer::SetFrame(const float *data, size_t length) {
    if (data == nullptr || length < 2) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    frame_.assign(data, data + length);
    hasFrame_ = true;
    if (ready_) {
        DrawLocked();
    }
}

void GameRenderer::SetUiRects(const float *data, size_t length) {
    if (data == nullptr || length < 2) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    uiRects_.assign(data, data + length);
    uiDirty_ = true;
}

void GameRenderer::SetUiTexts(const std::vector<std::string> &texts, const float *params, size_t paramCount) {
    std::lock_guard<std::mutex> lock(mutex_);
    uiTexts_ = texts;
    if (params != nullptr && paramCount > 0) {
        uiTextParams_.assign(params, params + paramCount);
    } else {
        uiTextParams_.clear();
    }
    uiDirty_ = true;
}

void GameRenderer::ReleaseSurface() {
    std::lock_guard<std::mutex> lock(mutex_);
    ReleaseEgl();
}

bool GameRenderer::EnsureEgl(void *window) {
    if (ready_) {
        return true;
    }
    if (window == nullptr) {
        return false;
    }
    window_ = window;

    eglDisplay_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (eglDisplay_ == EGL_NO_DISPLAY) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "eglGetDisplay failed");
        return false;
    }
    EGLint major = 0;
    EGLint minor = 0;
    if (!eglInitialize(eglDisplay_, &major, &minor)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "eglInitialize failed");
        return false;
    }
    const EGLint configAttribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLint numConfigs = 0;
    if (!eglChooseConfig(eglDisplay_, configAttribs, &eglConfig_, 1, &numConfigs) || numConfigs < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "eglChooseConfig failed");
        return false;
    }
    eglSurface_ = eglCreateWindowSurface(eglDisplay_, eglConfig_,
                                         reinterpret_cast<EGLNativeWindowType>(window), nullptr);
    if (eglSurface_ == EGL_NO_SURFACE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "eglCreateWindowSurface failed");
        return false;
    }
    const EGLint contextAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    eglContext_ = eglCreateContext(eglDisplay_, eglConfig_, EGL_NO_CONTEXT, contextAttribs);
    if (eglContext_ == EGL_NO_CONTEXT) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "eglCreateContext failed");
        return false;
    }
    if (!eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "eglMakeCurrent failed");
        return false;
    }
    if (!EnsureProgram()) {
        return false;
    }
    if (!EnsureTextureProgram()) {
        return false;
    }
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    ready_ = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, GAME_LOG_DOMAIN, GAME_LOG_TAG,
                 "EGL ready %{public}dx%{public}d", widthPx_, heightPx_);
    return true;
}

bool GameRenderer::EnsureProgram() {
    if (program_ != 0) {
        return true;
    }
    const char *attribs[] = {"a_corner", "a_pos", "a_size", "a_color", "a_radius", "a_glow"};
    program_ = LinkProgram(VERTEX_SHADER, FRAGMENT_SHADER, attribs, 6);
    if (program_ == 0) {
        return false;
    }
    viewportLoc_ = glGetUniformLocation(program_, "u_viewport");
    glGenBuffers(1, &vbo_);
    return true;
}

bool GameRenderer::EnsureTextureProgram() {
    if (texProgram_ != 0) {
        return true;
    }
    const char *attribs[] = {"a_pos", "a_uv"};
    texProgram_ = LinkProgram(TEX_VERTEX_SHADER, TEX_FRAGMENT_SHADER, attribs, 2);
    if (texProgram_ == 0) {
        return false;
    }
    texViewportLoc_ = glGetUniformLocation(texProgram_, "u_viewport");
    texSamplerLoc_ = glGetUniformLocation(texProgram_, "u_tex");
    glGenBuffers(1, &texVbo_);
    return true;
}

void GameRenderer::ReleaseUi() {
    if (uiCanvas_ != nullptr) {
        OH_Drawing_CanvasDestroy(uiCanvas_);
        uiCanvas_ = nullptr;
    }
    if (uiBitmap_ != nullptr) {
        OH_Drawing_BitmapDestroy(uiBitmap_);
        uiBitmap_ = nullptr;
    }
    // 共享字体集合不销毁（官方约定：供多个 Typography 复用）
    fontCollection_ = nullptr;
    if (uiTexture_ != 0) {
        glDeleteTextures(1, &uiTexture_);
        uiTexture_ = 0;
    }
    uiTexW_ = 0;
    uiTexH_ = 0;
}

void GameRenderer::ReleaseEgl() {
    if (eglDisplay_ != EGL_NO_DISPLAY && eglContext_ != EGL_NO_CONTEXT) {
        eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_);
        ReleaseUi();
        if (program_ != 0) {
            glDeleteProgram(program_);
            program_ = 0;
        }
        if (vbo_ != 0) {
            glDeleteBuffers(1, &vbo_);
            vbo_ = 0;
        }
        if (texProgram_ != 0) {
            glDeleteProgram(texProgram_);
            texProgram_ = 0;
        }
        if (texVbo_ != 0) {
            glDeleteBuffers(1, &texVbo_);
            texVbo_ = 0;
        }
        eglMakeCurrent(eglDisplay_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    if (eglDisplay_ != EGL_NO_DISPLAY) {
        if (eglSurface_ != EGL_NO_SURFACE) {
            eglDestroySurface(eglDisplay_, eglSurface_);
        }
        if (eglContext_ != EGL_NO_CONTEXT) {
            eglDestroyContext(eglDisplay_, eglContext_);
        }
        eglTerminate(eglDisplay_);
    }
    program_ = 0;
    vbo_ = 0;
    viewportLoc_ = -1;
    texProgram_ = 0;
    texVbo_ = 0;
    eglDisplay_ = EGL_NO_DISPLAY;
    eglSurface_ = EGL_NO_SURFACE;
    eglContext_ = EGL_NO_CONTEXT;
    window_ = nullptr;
    ready_ = false;
    uiDirty_ = true;
}

void GameRenderer::UploadFrameLocked() {
    size_t available = frame_.size() >= 2 ? (frame_.size() - 2) / FLOATS_PER_ITEM : 0;
    size_t count = static_cast<size_t>(std::max(0.0f, frame_.empty() ? 0.0f : frame_[0]));
    count = std::min(count, available);
    vertices_.clear();
    vertices_.resize(count * VERTICES_PER_ITEM * FLOATS_PER_VERTEX);
    size_t cursor = 0;
    static const float corners[VERTICES_PER_ITEM][2] = {
        {0.0f, 0.0f}, {1.0f, 0.0f}, {0.0f, 1.0f},
        {1.0f, 0.0f}, {1.0f, 1.0f}, {0.0f, 1.0f}
    };
    for (size_t i = 0; i < count; ++i) {
        const float *item = frame_.data() + 2 + i * FLOATS_PER_ITEM;
        for (int v = 0; v < VERTICES_PER_ITEM; ++v) {
            vertices_[cursor++] = corners[v][0];
            vertices_[cursor++] = corners[v][1];
            vertices_[cursor++] = item[0];
            vertices_[cursor++] = item[1];
            vertices_[cursor++] = item[2];
            vertices_[cursor++] = item[3];
            vertices_[cursor++] = item[4];
            vertices_[cursor++] = item[5];
            vertices_[cursor++] = item[6];
            vertices_[cursor++] = item[7];
            vertices_[cursor++] = item[8];
            vertices_[cursor++] = item[9];
        }
    }
}

void GameRenderer::DrawBoardLocked() {
    glViewport(0, 0, widthPx_, heightPx_);
    glClearColor(0.027f, 0.035f, 0.059f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    if (!hasFrame_ || frame_.empty()) {
        return;
    }
    UploadFrameLocked();
    if (vertices_.empty()) {
        return;
    }
    glUseProgram(program_);
    glUniform2f(viewportLoc_, static_cast<float>(widthPx_), static_cast<float>(heightPx_));
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glBufferData(GL_ARRAY_BUFFER,
                 static_cast<GLsizeiptr>(vertices_.size() * sizeof(float)),
                 vertices_.data(), GL_DYNAMIC_DRAW);

    const GLsizei stride = FLOATS_PER_VERTEX * static_cast<GLsizei>(sizeof(float));
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, nullptr);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const void *>(static_cast<GLsizeiptr>(2 * sizeof(float))));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const void *>(static_cast<GLsizeiptr>(4 * sizeof(float))));
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const void *>(static_cast<GLsizeiptr>(6 * sizeof(float))));
    glEnableVertexAttribArray(4);
    glVertexAttribPointer(4, 1, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const void *>(static_cast<GLsizeiptr>(10 * sizeof(float))));
    glEnableVertexAttribArray(5);
    glVertexAttribPointer(5, 1, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const void *>(static_cast<GLsizeiptr>(11 * sizeof(float))));

    glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(vertices_.size() / FLOATS_PER_VERTEX));
    for (int i = 0; i < 6; ++i) {
        glDisableVertexAttribArray(i);
    }
}

void GameRenderer::RenderUiLocked() {
    if (widthPx_ <= 0 || heightPx_ <= 0) {
        return;
    }
    if (uiBitmap_ == nullptr || uiTexW_ != widthPx_ || uiTexH_ != heightPx_) {
        ReleaseUi();
        const OH_Drawing_BitmapFormat format = {COLOR_FORMAT_RGBA_8888, ALPHA_FORMAT_UNPREMUL};
        uiBitmap_ = OH_Drawing_BitmapCreate();
        OH_Drawing_BitmapBuild(uiBitmap_, static_cast<uint32_t>(widthPx_),
                               static_cast<uint32_t>(heightPx_), &format);
        uiCanvas_ = OH_Drawing_CanvasCreate();
        OH_Drawing_CanvasBind(uiCanvas_, uiBitmap_);
        fontCollection_ = OH_Drawing_CreateSharedFontCollection();
        uiTexW_ = widthPx_;
        uiTexH_ = heightPx_;
        glGenTextures(1, &uiTexture_);
    }
    if (uiCanvas_ == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "ui: canvas null");
        return;
    }
    OH_Drawing_CanvasClear(uiCanvas_, 0x00000000);

    // 1) 矩形（按钮、卡片、遮罩、面板……）
    OH_Drawing_Brush *brush = OH_Drawing_BrushCreate();
    const size_t rectCount = uiRects_.size() >= 2
        ? std::min(static_cast<size_t>(std::max(0.0f, uiRects_[0])), (uiRects_.size() - 2) / FLOATS_PER_ITEM)
        : 0;
    for (size_t i = 0; i < rectCount; ++i) {
        const float *item = uiRects_.data() + 2 + i * FLOATS_PER_ITEM;
        const float x = item[0] * static_cast<float>(widthPx_);
        const float y = item[1] * static_cast<float>(heightPx_);
        const float w = item[2] * static_cast<float>(widthPx_);
        const float h = item[3] * static_cast<float>(heightPx_);
        if (w <= 0 || h <= 0) {
            continue;
        }
        OH_Drawing_BrushSetColor(brush, ColorFromFloats(item[4], item[5], item[6], item[7]));
        OH_Drawing_CanvasAttachBrush(uiCanvas_, brush);
        OH_Drawing_Rect *rect = OH_Drawing_RectCreate(x, y, x + w, y + h);
        const float radius = item[8] * std::min(w, h);
        OH_Drawing_RoundRect *roundRect = OH_Drawing_RoundRectCreate(rect, radius, radius);
        OH_Drawing_CanvasDrawRoundRect(uiCanvas_, roundRect);
        OH_Drawing_RoundRectDestroy(roundRect);
        OH_Drawing_RectDestroy(rect);
        OH_Drawing_CanvasDetachBrush(uiCanvas_);
    }
    OH_Drawing_BrushDestroy(brush);

    // 2) 文本（HUD、按钮文案、弹窗、调试日志）
    const size_t textCount = std::min(uiTexts_.size(), uiTextParams_.size() / FLOATS_PER_TEXT);
    for (size_t i = 0; i < textCount; ++i) {
        const float *p = uiTextParams_.data() + i * FLOATS_PER_TEXT;
        const std::string &text = uiTexts_[i];
        if (text.empty()) {
            continue;
        }
        const float sizePx = p[2] * static_cast<float>(heightPx_);
        if (sizePx <= 0.0f) {
            continue;
        }
        OH_Drawing_TextStyle *style = OH_Drawing_CreateTextStyle();
        OH_Drawing_SetTextStyleColor(style, ColorFromFloats(p[3], p[4], p[5], p[6]));
        OH_Drawing_SetTextStyleFontSize(style, sizePx);
        OH_Drawing_SetTextStyleFontWeight(style, p[8] > 0.5f ? FONT_WEIGHT_700 : FONT_WEIGHT_400);

        OH_Drawing_TypographyStyle *typoStyle = OH_Drawing_CreateTypographyStyle();
        OH_Drawing_TypographyCreate *handler = OH_Drawing_CreateTypographyHandler(typoStyle, fontCollection_);
        OH_Drawing_TypographyHandlerPushTextStyle(handler, style);
        OH_Drawing_TypographyHandlerAddText(handler, text.c_str());
        OH_Drawing_Typography *typography = OH_Drawing_CreateTypography(handler);
        OH_Drawing_TypographyLayout(typography, static_cast<double>(widthPx_));

        double drawX = p[0] * static_cast<float>(widthPx_);
        if (p[7] > 0.5 && p[7] < 1.5) {
            drawX -= OH_Drawing_TypographyGetLongestLine(typography) * 0.5;   // 居中
        } else if (p[7] >= 1.5) {
            drawX -= OH_Drawing_TypographyGetLongestLine(typography);          // 右对齐
        }
        const double drawY = p[1] * static_cast<float>(heightPx_);
        OH_Drawing_TypographyPaint(typography, uiCanvas_, drawX, drawY);

        OH_Drawing_DestroyTypography(typography);
        OH_Drawing_DestroyTypographyHandler(handler);
        OH_Drawing_DestroyTypographyStyle(typoStyle);
        OH_Drawing_DestroyTextStyle(style);
    }

    // 3) 上传为纹理
    if (uiTexture_ != 0) {
        glBindTexture(GL_TEXTURE_2D, uiTexture_);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, widthPx_, heightPx_, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, OH_Drawing_BitmapGetPixels(uiBitmap_));
    }
    uiDirty_ = false;
}

void GameRenderer::DrawUiLocked() {
    // 首次绘制时 bitmap/纹理都还没创建，必须先走一次 RenderUiLocked
    if (uiTexture_ == 0 || uiBitmap_ == nullptr || uiDirty_) {
        RenderUiLocked();
    }
    if (uiTexture_ == 0 || uiBitmap_ == nullptr) {
        return;
    }
    glUseProgram(texProgram_);
    glUniform2f(texViewportLoc_, static_cast<float>(widthPx_), static_cast<float>(heightPx_));
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, uiTexture_);
    glUniform1i(texSamplerLoc_, 0);

    float quad[24];
    size_t cursor = 0;
    PushQuad(quad, cursor, 0.0f, 0.0f, 1.0f, 1.0f);
    glBindBuffer(GL_ARRAY_BUFFER, texVbo_);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_DYNAMIC_DRAW);
    const GLsizei stride = 4 * static_cast<GLsizei>(sizeof(float));
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, nullptr);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const void *>(static_cast<GLsizeiptr>(2 * sizeof(float))));
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(0);
    glDisableVertexAttribArray(1);
}

void GameRenderer::DrawLocked() {
    if (!ready_ || eglSurface_ == EGL_NO_SURFACE) {
        return;
    }
    if (!eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_)) {
        return;
    }
    DrawBoardLocked();
    DrawUiLocked();
    eglSwapBuffers(eglDisplay_, eglSurface_);
}

void GameRenderer::OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window) {
    auto &self = GameRenderer::GetInstance();
    uint64_t width = 0;
    uint64_t height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);

    std::lock_guard<std::mutex> lock(self.mutex_);
    self.widthPx_ = static_cast<int>(width);
    self.heightPx_ = static_cast<int>(height);
    if (!self.EnsureEgl(window)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "OnSurfaceCreated: EGL init failed");
        return;
    }
    self.uiDirty_ = true;
    if (self.hasFrame_) {
        self.DrawLocked();
    }
}

void GameRenderer::OnSurfaceChangedCB(OH_NativeXComponent *component, void *window) {
    auto &self = GameRenderer::GetInstance();
    uint64_t width = 0;
    uint64_t height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);

    std::lock_guard<std::mutex> lock(self.mutex_);
    if (self.widthPx_ == static_cast<int>(width) && self.heightPx_ == static_cast<int>(height)) {
        return;
    }
    self.widthPx_ = static_cast<int>(width);
    self.heightPx_ = static_cast<int>(height);
    self.uiDirty_ = true;
    if (self.ready_ && self.hasFrame_) {
        self.DrawLocked();
    }
}

void GameRenderer::OnSurfaceDestroyedCB(OH_NativeXComponent *component, void *window) {
    (void)component;
    (void)window;
    GameRenderer::GetInstance().ReleaseSurface();
    OH_LOG_Print(LOG_APP, LOG_INFO, GAME_LOG_DOMAIN, GAME_LOG_TAG, "OnSurfaceDestroyed");
}

void GameRenderer::DispatchTouchEventCB(OH_NativeXComponent *component, void *window) {
    if (component == nullptr || window == nullptr) {
        return;
    }
    OH_NativeXComponent_TouchEvent touchEvent;
    if (OH_NativeXComponent_GetTouchEvent(component, window, &touchEvent) != 0) {
        return;
    }
    GameRenderer &self = GameRenderer::GetInstance();
    std::lock_guard<std::mutex> lock(self.mutex_);
    if (self.widthPx_ <= 0 || self.heightPx_ <= 0) {
        return;
    }
    const float nx = touchEvent.x / static_cast<float>(self.widthPx_);
    const float ny = touchEvent.y / static_cast<float>(self.heightPx_);
    switch (touchEvent.type) {
        case OH_NATIVEXCOMPONENT_DOWN:
            self.touchDown_ = true;
            self.touchDownX_ = nx;
            self.touchDownY_ = ny;
            self.touchMoveX_ = nx;
            self.touchMoveY_ = ny;
            break;
        case OH_NATIVEXCOMPONENT_MOVE:
            self.touchMove_ = true;
            self.touchMoveX_ = nx;
            self.touchMoveY_ = ny;
            break;
        case OH_NATIVEXCOMPONENT_UP:
        case OH_NATIVEXCOMPONENT_CANCEL:
            self.touchMoveX_ = nx;
            self.touchMoveY_ = ny;
            self.touchUp_ = true;
            break;
        default:
            break;
    }
}

void GameRenderer::GetSurfaceSize(float *out2) {
    if (out2 == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    out2[0] = static_cast<float>(widthPx_);
    out2[1] = static_cast<float>(heightPx_);
}

void GameRenderer::PollTouch(float *out8) {
    if (out8 == nullptr) {
        return;
    }
    for (int i = 0; i < 8; ++i) {
        out8[i] = 0.0f;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    if (touchDown_) {
        out8[0] = 1.0f;
        out8[1] = touchDownX_;
        out8[2] = touchDownY_;
        touchDown_ = false;
    }
    if (touchMove_) {
        out8[3] = 1.0f;
        out8[4] = touchMoveX_;
        out8[5] = touchMoveY_;
        touchMove_ = false;
    }
    if (touchUp_) {
        out8[6] = 1.0f;
        touchUp_ = false;
    }
}
