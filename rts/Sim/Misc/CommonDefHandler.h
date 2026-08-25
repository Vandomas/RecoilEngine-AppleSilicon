/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */

#ifndef COMMON_DEF_HANDLER_H
#define COMMON_DEF_HANDLER_H

#include <string>

struct GuiSoundSet;
struct GuiSoundSetData;

class CommonDefHandler {
public:
	static void InitStatic();
	static void KillStatic();

	static void AddSoundSetData(GuiSoundSet& soundSet, const std::string& fileName, float volume);

	// queues a soundfile for background preload, resolves names like LoadSoundFile
	static void PreloadSoundFile(const std::string& fileName);

	static GuiSoundSetData& GetSoundSetData(size_t idx);

	static size_t SoundSetDataCount();

	// loads a soundfile, adds "sounds/" prefix and ".wav" extension if necessary
	static int LoadSoundFile(const std::string& fileName);
};

#endif

