package com.masjid.monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ScreenOnReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "ScreenOnReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SCREEN_ON,
            Intent.ACTION_USER_PRESENT -> {
                Log.d(TAG, "Screen is on, ensuring Masjid Monitor is running...")
                
                // Check if MainActivity is already running
                val mainIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                
                context.startActivity(mainIntent)
                
                // Restart prayer service
                val serviceIntent = Intent(context, PrayerService::class.java)
                context.startService(serviceIntent)
                
                Log.d(TAG, "Masjid Monitor brought to front")
            }
        }
    }
}
