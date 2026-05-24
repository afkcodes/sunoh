package com.sunoh.sunoh

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service requires MainActivity to extend AudioServiceActivity (which
// itself extends FlutterFragmentActivity). Without this, AudioService.init
// fails with "The Activity class declared in your AndroidManifest.xml is
// wrong or has not provided the correct FlutterEngine".
class MainActivity : AudioServiceActivity()
