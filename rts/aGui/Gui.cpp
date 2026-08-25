/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */

#include "System/Input/InputHandler.h"
#include "Gui.h"

#include <SDL_events.h>
#include <cmath>

#include "GuiElement.h"
#include "Rendering/GlobalRendering.h"
#include "Rendering/GL/myGL.h"
#include "System/Log/ILog.h"


namespace agui
{

Gui::Gui()
{
	inputCon = input.AddHandler([this](const SDL_Event& event) { return this->HandleEvent(event); });
}

#ifdef HEADLESS
void Gui::Draw() {}
#else
void Gui::Draw()
{
	Clean();

	glDisable(GL_TEXTURE_2D);
	glDisable(GL_ALPHA_TEST);
	glEnable(GL_BLEND);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	gluOrtho2D(0, 1, 0, 1);
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	for (ElList::reverse_iterator it = elements.rbegin(); it != elements.rend(); ++it) {
		(*it).element->Draw();
	}
}
#endif

void Gui::Clean() {
	for (ElList::iterator it = toBeAdded.begin(); it != toBeAdded.end(); ++it)
	{
		bool duplicate = false;
		for (ElList::iterator elIt = elements.begin(); elIt != elements.end(); ++elIt)
		{
			if (it->element == elIt->element)
			{
				LOG_L(L_DEBUG, "Gui::AddElement: skipping duplicated object");
				duplicate = true;
				break;
			}
		}
		if (!duplicate)
		{
			if (it->asBackground)
				elements.push_back(*it);
			else
				elements.push_front(*it);
		}
	}
	toBeAdded.clear();

	for (ElList::iterator it = toBeRemoved.begin(); it != toBeRemoved.end(); ++it)
	{
		for (ElList::iterator elIt = elements.begin(); elIt != elements.end(); ++elIt)
		{
			if (it->element == elIt->element)
			{
				delete (elIt->element);
				elements.erase(elIt);
				break;
			}
		}
	}
	toBeRemoved.clear();
}

Gui::~Gui() {
	Clean();
}

void Gui::AddElement(GuiElement* elem, bool asBackground)
{
	toBeAdded.push_back(GuiItem(elem,asBackground));
}

void Gui::RmElement(GuiElement* elem)
{
	// has to be delayed, otherwise deleting a button during a callback would segfault
	for (ElList::iterator it = elements.begin(); it != elements.end(); ++it) {
		if ((*it).element == elem) {
			toBeRemoved.push_back(GuiItem(elem,true));
			break;
		}
	}
}

void Gui::UpdateScreenGeometry(int screenx, int screeny, int screenOffsetX, int screenOffsetY)
{
	GuiElement::UpdateDisplayGeo(screenx, screeny, screenOffsetX, screenOffsetY);
}

bool Gui::MouseOverElement(const GuiElement* elem, int x, int y) const
{
	for (ElList::const_iterator it = elements.begin(); it != elements.end(); ++it)
	{
		if (it->element->MouseOver(x, y))
		{
			if (it->element == elem)
				return true;
			else
				return false;
		}
	}
	return false;
}

bool Gui::HandleEvent(const SDL_Event& ev)
{
	SDL_Event event = ev;
#ifdef __APPLE__
	if (event.type == SDL_MOUSEMOTION || event.type == SDL_MOUSEBUTTONDOWN || event.type == SDL_MOUSEBUTTONUP) {
		int winW = 1, winH = 1;
		if (globalRendering->sdlWindow != nullptr)
			SDL_GetWindowSize(globalRendering->sdlWindow, &winW, &winH);
		const double sx = (winW > 1)? double(globalRendering->viewSizeX - 1) / double(winW - 1): 1.0;
		const double sy = (winH > 1)? double(globalRendering->viewSizeY - 1) / double(winH - 1): 1.0;
		if (event.type == SDL_MOUSEMOTION) {
			event.motion.x = int(std::lround(event.motion.x * sx));
			event.motion.y = int(std::lround(event.motion.y * sy));
		} else {
			event.button.x = int(std::lround(event.button.x * sx));
			event.button.y = int(std::lround(event.button.y * sy));
		}
	}
#endif
	ElList::iterator handler = elements.end();
	for (ElList::iterator it = elements.begin(); it != elements.end(); ++it)
	{
		if (it->element->HandleEvent(event))
		{
			handler = it;
			break;
		}
	}
	if (handler != elements.end() && !handler->asBackground)
	{
		elements.push_front(*handler);
		elements.erase(handler);
	}
	return false;
}

Gui* gui = nullptr;

}

