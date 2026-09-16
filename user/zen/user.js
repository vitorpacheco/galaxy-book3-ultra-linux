// Firefox / Zen: use the camera through PipeWire (libcamera) instead of
// raw V4L2 nodes, which only deliver Bayer data on IPU6 laptops.
user_pref("media.webrtc.camera.allow-pipewire", true);
