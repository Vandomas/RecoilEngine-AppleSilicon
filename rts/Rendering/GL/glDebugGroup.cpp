#include "glDebugGroup.hpp"

#include "myGL.h"

GL::DebugGroupImpl::DebugGroupImpl(uint32_t id, const char* messsage)
{
	glPushDebugGroup(GL_DEBUG_SOURCE_APPLICATION, id, -1, messsage);
	// a group only lives in Mesa's bookkeeping, a marker message travels down to the driver
	// as a command buffer label. MoltenVK lists those labels next to the encoder that
	// faulted when the gpu dies, which is the only way to learn which pass was drawing
	glDebugMessageInsert(GL_DEBUG_SOURCE_APPLICATION, GL_DEBUG_TYPE_MARKER, id, GL_DEBUG_SEVERITY_NOTIFICATION, -1, messsage);
}

GL::DebugGroupImpl::~DebugGroupImpl()
{
	glPopDebugGroup();
}

std::unique_ptr<GL::DebugGroup> GL::DebugGroup::GetScoped(uint32_t id, const char* messsage)
{
	if (GLAD_GL_KHR_debug)
		return std::make_unique<GL::DebugGroupImpl>(id, messsage);
	else
		return std::make_unique<GL::DebugGroupNoop>(id, messsage);
}
