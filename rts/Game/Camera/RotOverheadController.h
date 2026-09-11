/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */

#pragma once

#include "CameraController.h"
#include "Game/Camera.h"

class CRotOverheadController : public CCameraController
{
public:
	CRotOverheadController();
	~CRotOverheadController() override;

	const std::string GetName() const { return "rot"; }

	void KeyMove(float3 move);
	void MouseMove(float3 move);
	void ScreenEdgeMove(float3 move);
	void MouseWheelMove(float move);
	void MouseWheelMove(float move, const float3& newDir) { MouseWheelMove(move); }

	void SetPos(const float3& newPos);
	void SetRot(const float3& newRot) { rot = newRot; };

	float3 SwitchFrom() const;
	void SwitchTo(const CCameraController* oldCam, const bool showText);

	void GetState(StateMap& sm) const;
	bool SetState(const StateMap& sm);
	float3 GetRot() const { return rot; }
	float3 GetDir() const {	return CCamera::GetFwdFromRot(rot); }

	void Update();
	void ConfigNotify(const std::string& key, const std::string& value);

private:
	float3 rot;
	float mouseScale;
	float oldHeight;
	bool clampToMap;
};
