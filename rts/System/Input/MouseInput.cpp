/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */

/*
	This workaround fixes the windows slow mouse movement problem
	(happens on full-screen mode + pressing keys).
	The code hacks around the mouse input from DirectInput,
	which SDL uses in full-screen mode.
	Instead it installs a window message proc and reads input from WM_MOUSEMOVE.
	On non-windows, the normal SDL events are used for mouse input

	new:
	It also workarounds a issue with SDL+windows and hardware cursors
	(->it has to block WM_SETCURSOR),
	so it is used now always even in window mode!

	newer:
	SDL_Event struct is used for new input handling.
	Several people confirmed its working.
*/


#include <algorithm>
#include <cmath>
#include <cstdlib>
#include "MouseInput.h"
#include "InputHandler.h"

#include "Game/UI/MouseHandler.h"
#include "Rendering/GlobalRendering.h"
#include "System/MainDefines.h"
#include "System/SafeUtil.h"
#include "System/Log/ILog.h"
#include "System/Config/ConfigHandler.h"

#include <SDL_events.h>
#include <SDL_hints.h>
#include <SDL_syswm.h>
#include <SDL_touch.h>
#ifdef __APPLE__
#include <SDL_video.h>
#endif


// Diagnostic input-method logging (KEEP; off by default).
//
// Rationale: several input reports (issue #7 edge-scroll, trackpad / precise-
// scroll complaints) arrive without the reporter's device, and we cannot tell
// from an ordinary infolog what the engine actually received. Setting the
// environment variable SPRING_DBG_INPUT=1 makes every SDL mouse/wheel/motion
// event get recorded under the "Input" log section with its SOURCE (physical
// mouse vs touch/trackpad, via SDL_TOUCH_MOUSEID), scroll direction
// (normal/flipped) and — the crucial macOS bit — precise/pixel deltas
// (trackpad two-finger + momentum scrolling) vs integer line deltas (a notched
// wheel). A user reporting a scroll/trackpad/edge issue can then attach an
// infolog that fully describes the event stream. Lines are tagged "[input]".
#define LOG_SECTION_INPUT "Input"
LOG_REGISTER_SECTION_GLOBAL(LOG_SECTION_INPUT)
#ifdef LOG_SECTION_CURRENT
	#undef LOG_SECTION_CURRENT
#endif
#define LOG_SECTION_CURRENT LOG_SECTION_INPUT

namespace {
	// Checked once and cached; zero runtime cost when disabled.
	static bool InputDbgEnabled()
	{
		static const bool enabled = []() {
			const char* e = getenv("SPRING_DBG_INPUT");
			return (e != nullptr && e[0] != '\0' && e[0] != '0');
		}();
		return enabled;
	}

	// SDL sets `which` to SDL_TOUCH_MOUSEID for events synthesized from touch
	// input; a real device id means a physical mouse/trackpad HID.
	static const char* MouseSrcStr(Uint32 which)
	{
		return (which == SDL_TOUCH_MOUSEID) ? "touch/trackpad" : "mouse";
	}
}


IMouseInput* mouseInput = nullptr;

CONFIG(float, MouseRelativeSpeedScale)
	.defaultValue(1.0f)
	.minimumValue(0.1f)
	.maximumValue(10.0f)
	.description("Scales mouse movement while in relative mode (locked camera, MMB scroll). 1.0 = raw device speed; raise it if panning feels slower than the OS pointer.");

IMouseInput::IMouseInput(bool relModeWarp)
{
	inputCon = input.AddHandler([this](const SDL_Event& event) { return this->HandleSDLMouseEvent(event); });
	#ifndef HEADLESS
	if (configHandler != nullptr) {
		const float relSpeedScale = configHandler->GetFloat("MouseRelativeSpeedScale");
		if (relSpeedScale != 1.0f) {
			char buf[32];
			snprintf(buf, sizeof(buf), "%g", relSpeedScale);
			SDL_SetHint(SDL_HINT_MOUSE_RELATIVE_SPEED_SCALE, buf);
		}
	}
	// Windows 10 FCU (Fall Creators Update) causes spurious SDL_MOUSEMOTION
	// events to be generated with SDL_HINT_MOUSE_RELATIVE_MODE_WARP enabled
	//
	// while Spring did not previously set this hint and SDL defaults to raw
	// input, the update also affects MMB scrolling via SDL_WarpMouseInWindow
	// (our ancient manually implemented method of achieving relative motion)
	//
	// win32 SDL hides these events in 2.0.8 only if mouse->relative_mode_warp
	// (which configures relative mouse mode to *internally* use mouse warping
	// instead of raw input and gets toggled by SDL_SetRelativeMouseMode based
	// on the hint given here); the alternative to RMW would be to *duplicate*
	// the SDL patch in WarpPos
	SDL_SetHint(SDL_HINT_MOUSE_RELATIVE_MODE_WARP, relModeWarp? "1": "0");
	#endif
}

IMouseInput::~IMouseInput()
{
	#ifndef HEADLESS
	SDL_SetHint(SDL_HINT_MOUSE_RELATIVE_MODE_WARP, "0");
	#endif
}


#ifdef __APPLE__
// SDL emits mouse events in logical (point) coordinates. On the macOS
// surfaceless+pbuffer path the engine viewport is in backing-pixel
// coordinates (viewSize/winSize are tied to the pbuffer FBO; see
// GlobalRendering::ReadWindowPosAndSize). Without rescaling, windowed-
// mode clicks land at half the cursor position on Retina displays.
static int2 ScaleMouseCoords(int x, int y)
{
	int sdlW = 1, sdlH = 1;
	if (globalRendering->sdlWindow != nullptr)
		SDL_GetWindowSize(globalRendering->sdlWindow, &sdlW, &sdlH);
	if (sdlW < 1) sdlW = 1;
	if (sdlH < 1) sdlH = 1;
	// Map the last reachable logical coordinate (sdl size - 1) onto the last
	// pixel coordinate (viewSize - 1): plain size-ratio scaling tops out 2px
	// short of the right/bottom edge on 2x Retina, which broke edge scrolling
	// there (engine edge tests compare against viewSize - 1; issue #7).
	const int scaledX = (sdlW > 1)
		? (int)std::lround((double)x * (double)(globalRendering->viewSizeX - 1) / (double)(sdlW - 1))
		: 0;
	const int scaledY = (sdlH > 1)
		? (int)std::lround((double)y * (double)(globalRendering->viewSizeY - 1) / (double)(sdlH - 1))
		: 0;
	return int2(scaledX, scaledY);
}

static float ScaleMouseDelta(float d, int sdlSize, int viewSize)
{
	if (sdlSize < 1) sdlSize = 1;
	return d * (float)viewSize / (float)sdlSize;
}
#endif


bool IMouseInput::HandleSDLMouseEvent(const SDL_Event& event)
{
	switch (event.type) {
		case SDL_MOUSEMOTION: {
#ifdef __APPLE__
			mousepos = ScaleMouseCoords(event.motion.x, event.motion.y);

			if (mouse != nullptr) {
				int sdlW = 1, sdlH = 1;
				if (globalRendering->sdlWindow != nullptr)
					SDL_GetWindowSize(globalRendering->sdlWindow, &sdlW, &sdlH);
				mouse->MouseMove(mousepos.x, mousepos.y,
					ScaleMouseDelta(event.motion.xrel, sdlW, globalRendering->viewSizeX),
					ScaleMouseDelta(event.motion.yrel, sdlH, globalRendering->viewSizeY));
			}
#else
			mousepos = int2(event.motion.x, event.motion.y);

			if (mouse != nullptr)
				mouse->MouseMove(mousepos.x, mousepos.y, event.motion.xrel, event.motion.yrel);
#endif

			if (InputDbgEnabled()) {
				// Plain motion floods, so throttle it to ~1 line/100ms; but ALWAYS
				// log a drag (any button held — this covers middle-drag scrolling)
				// and motion that reaches a viewport edge (edge-scroll reports).
				static Uint32 lastMotionLogMs = 0;
				const bool dragging = (event.motion.state != 0);
				const bool atEdge =
					(mousepos.x <= globalRendering->viewPosX) ||
					(mousepos.y <= globalRendering->viewWindowOffsetY) ||
					(mousepos.x >= globalRendering->viewPosX + globalRendering->viewSizeX - 1) ||
					(mousepos.y >= globalRendering->viewWindowOffsetY + globalRendering->viewSizeY - 1);
				if (dragging || atEdge || (Uint32)(event.motion.timestamp - lastMotionLogMs) >= 100u) {
					lastMotionLogMs = event.motion.timestamp;
					LOG_L(L_NOTICE, "[input] motion src=%s pos=%d,%d rel=%d,%d btnmask=0x%02x%s%s",
						MouseSrcStr(event.motion.which), mousepos.x, mousepos.y,
						event.motion.xrel, event.motion.yrel, (unsigned)event.motion.state,
						dragging ? " DRAG" : "", atEdge ? " EDGE" : "");
				}
			}

		} break;
		case SDL_MOUSEBUTTONDOWN: {
#ifdef __APPLE__
			mousepos = ScaleMouseCoords(event.button.x, event.button.y);
#else
			mousepos = int2(event.button.x, event.button.y);
#endif

			// suppress if the button is already held via input emulation
			if (mouse != nullptr && !mouse->IsButtonEmulated(event.button.button))
				mouse->MousePress(mousepos.x, mousepos.y, event.button.button);

			if (InputDbgEnabled())
				LOG_L(L_NOTICE, "[input] button DOWN src=%s btn=%u clicks=%u pos=%d,%d",
					MouseSrcStr(event.button.which), (unsigned)event.button.button,
					(unsigned)event.button.clicks, mousepos.x, mousepos.y);

		} break;
		case SDL_MOUSEBUTTONUP: {
#ifdef __APPLE__
			mousepos = ScaleMouseCoords(event.button.x, event.button.y);
#else
			mousepos = int2(event.button.x, event.button.y);
#endif

			if (mouse != nullptr && !mouse->IsButtonEmulated(event.button.button))
				mouse->MouseRelease(mousepos.x, mousepos.y, event.button.button);

			if (InputDbgEnabled())
				LOG_L(L_NOTICE, "[input] button UP   src=%s btn=%u clicks=%u pos=%d,%d",
					MouseSrcStr(event.button.which), (unsigned)event.button.button,
					(unsigned)event.button.clicks, mousepos.x, mousepos.y);

		} break;
		case SDL_MOUSEWHEEL: {
			if (InputDbgEnabled()) {
				// The key diagnostic for scroll/trackpad reports. On macOS a
				// notched wheel arrives as integer line deltas (preciseY == y);
				// trackpad two-finger scrolling and momentum/inertial scrolling
				// arrive as high-frequency fractional precise (pixel) deltas
				// (preciseY != y). "flipped" == macOS natural-scroll direction.
				const bool flipped = (event.wheel.direction == SDL_MOUSEWHEEL_FLIPPED);
				const bool precise = (event.wheel.preciseX != (float)event.wheel.x) ||
				                     (event.wheel.preciseY != (float)event.wheel.y);
				LOG_L(L_NOTICE, "[input] wheel  src=%s dir=%s line=%d,%d precise=%.4f,%.4f %s",
					MouseSrcStr(event.wheel.which), flipped ? "flipped" : "normal",
					event.wheel.x, event.wheel.y, event.wheel.preciseX, event.wheel.preciseY,
					precise ? "PRECISE/pixel" : "LINE/notch");
			}

			if (mouse != nullptr)
				mouse->MouseWheel(event.wheel.y);

		} break;
		case SDL_WINDOWEVENT: {
			switch (event.window.event) {
				case SDL_WINDOWEVENT_ENTER: {
					if (InputDbgEnabled())
						LOG_L(L_NOTICE, "[input] window ENTER");
					if (mouse != nullptr)
						mouse->WindowEnter();
				} break;
				case SDL_WINDOWEVENT_LEAVE: {
					// mouse left window; set pos internally to view center-pixel to prevent endless scrolling
					mousepos = {
						globalRendering->viewPosX          + (globalRendering->viewSizeX >> 1),
						globalRendering->viewWindowOffsetY + (globalRendering->viewSizeY >> 1)
					};

					if (InputDbgEnabled())
						LOG_L(L_NOTICE, "[input] window LEAVE");
					if (mouse != nullptr)
						mouse->WindowLeave();
				} break;
			}
		} break;
	}

	return false;
}

//////////////////////////////////////////////////////////////////////

#if defined(_WIN32) && !defined(HEADLESS)

class CWin32MouseInput : public IMouseInput
{
public:
	static CWin32MouseInput* inst;

	LONG_PTR sdl_wndproc;
	HWND wnd;
	HCURSOR hCursor;

	static LRESULT CALLBACK SpringWndProc(HWND wnd, UINT msg, WPARAM wParam, LPARAM lParam)
	{
		switch (msg) {
			case WM_SETCURSOR: {
				if (inst->hCursor != nullptr) {
					const Uint16 hittest = LOWORD(lParam);

					if (hittest == HTCLIENT) {
						SetCursor(inst->hCursor);
						return TRUE;
					}
				}
			} break;
		}
		return CallWindowProc((WNDPROC)inst->sdl_wndproc, wnd, msg, wParam, lParam);
	}

	void SetWMMouseCursor(void* wmcursor)
	{
		hCursor = (HCURSOR)wmcursor;
	}

	void InstallWndCallback()
	{
		SDL_SysWMinfo info;
		SDL_VERSION(&info.version);
		if (!SDL_GetWindowWMInfo(globalRendering->GetWindow(), &info))
			return;

		wnd = info.info.win.window;

		LONG_PTR cur_wndproc = GetWindowLongPtr(wnd, GWLP_WNDPROC);

		if (cur_wndproc != (LONG_PTR)SpringWndProc) {
			sdl_wndproc = GetWindowLongPtr(wnd, GWLP_WNDPROC);
			SetWindowLongPtr(wnd, GWLP_WNDPROC, (LONG_PTR)SpringWndProc);
		}
	}

	CWin32MouseInput(bool relModeWarp): IMouseInput(relModeWarp)
	{
		inst = this;
		hCursor = nullptr;
		sdl_wndproc = 0;
		wnd = 0;

		InstallWndCallback();
	}
	~CWin32MouseInput()
	{
		// reinstall the SDL window proc
		SetWindowLongPtr(wnd, GWLP_WNDPROC, sdl_wndproc);
	}
};

CWin32MouseInput* CWin32MouseInput::inst = nullptr;


alignas(CWin32MouseInput) static std::byte mouseInputMem[sizeof(CWin32MouseInput)];
#else
alignas(IMouseInput) static std::byte mouseInputMem[sizeof(IMouseInput)];
#endif



#if 1
static SDL_Event events[100];
#endif

bool IMouseInput::SetPos(int2 pos)
{
	if (!globalRendering->active)
		return false;

	// calling SDL_WarpMouse at 300fps eats ~5% cpu usage, so only update when needed
	if (pos.x == mousepos.x && pos.y == mousepos.y)
		return false;

	return (mousepos = pos, true);
}

bool IMouseInput::WarpPos(int2 pos)
{
	#if __unix__
		/* Needed for SDL2+Wayland where warping isn't allowed otherwise, works fine with X11.
		 * One would think there should be a corresponding `SDL_ShowCursor(SDL_ENABLE);` below,
		 * but apparently this prevents this work-around from working (?!). */
		SDL_ShowCursor(SDL_DISABLE);
	#endif

#ifdef __APPLE__
	// pos is in engine view coordinates (backing pixels — the inverse of
	// ScaleMouseCoords); SDL_WarpMouseInWindow expects logical points. Warping
	// with pixel coords lands at 2x the intended position on Retina (and gets
	// clamped at the window edge). Map [0, viewSize-1] -> [0, sdlSize-1].
	{
		int sdlW = 1, sdlH = 1;
		if (globalRendering->sdlWindow != nullptr)
			SDL_GetWindowSize(globalRendering->sdlWindow, &sdlW, &sdlH);
		const int vsx = std::max(2, globalRendering->viewSizeX);
		const int vsy = std::max(2, globalRendering->viewSizeY);
		pos.x = (int)std::lround((double)pos.x * (double)(std::max(2, sdlW) - 1) / (double)(vsx - 1));
		pos.y = (int)std::lround((double)pos.y * (double)(std::max(2, sdlH) - 1) / (double)(vsy - 1));
	}
#endif

	SDL_WarpMouseInWindow(globalRendering->GetWindow(), pos.x, pos.y);

	// SDL_WarpMouse generates SDL_MOUSEMOTION events
	// in `middle click scrolling` those SDL generated ones would point into
	// the opposite direction the user moved the mouse, and so events would
	// cancel each other -> camera wouldn't move at all or jitter
	// need to catch the SDL generated events and delete them from its queue
	//
	// NOTE [2018]:
	//   the above comment dates back to 2010, but also describes the recent
	//   Windows 10 FCU bug with relative mode warping which similarly relies
	//   on WMIW
	#if 1
	SDL_PumpEvents();
	SDL_PeepEvents(&events[0], sizeof(events) / sizeof(events[0]), SDL_GETEVENT, SDL_MOUSEMOTION, SDL_MOUSEMOTION);
	#else
	// should be equivalent, but for some reason is not
	SDL_FlushEvent(SDL_MOUSEMOTION);
	#endif

	return true;
}



IMouseInput* IMouseInput::GetInstance(bool relModeWarp)
{
	if (mouseInput == nullptr) {
#if defined(_WIN32) && !defined(HEADLESS)
		mouseInput = new (mouseInputMem) CWin32MouseInput(relModeWarp);
#else
		mouseInput = new (mouseInputMem) IMouseInput(relModeWarp);
#endif
	}

	return mouseInput;
}

void IMouseInput::FreeInstance(IMouseInput* mouseInp) {
	assert(mouseInp == mouseInput);
	spring::SafeDestruct(mouseInp);
	memset(mouseInputMem, 0, sizeof(mouseInputMem));
	mouseInput = nullptr;
}

