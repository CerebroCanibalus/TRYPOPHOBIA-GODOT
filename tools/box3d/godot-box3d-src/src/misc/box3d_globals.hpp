#pragma once

// Extension-wide lifecycle hooks.

void box3d_initialize();

void box3d_deinitialize();

// The physics/box3d/worker_count setting, or the detected core count when it is 0 (auto).
int box3d_worker_count();

// The physics/box3d/sub_step_count setting, or 1 (the new safe default) when it is 0 (auto).
// Tripofobia patch M2: was hardcoded to 4, which caused 240 sub-steps/sec with 60 Hz physics.
int box3d_sub_step_count();
