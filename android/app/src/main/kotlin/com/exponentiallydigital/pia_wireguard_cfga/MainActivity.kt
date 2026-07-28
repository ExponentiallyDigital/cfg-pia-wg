package com.exponentiallydigital.pia_wireguard_cfga

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
           WindowManager.LayoutParams.FLAG_SECURE,
           WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }
}
