# Prevent R8/ProGuard from stripping FFmpegKit event channels and native hooks
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class org.ffmpeg.** { *; }
-dontwarn com.arthenica.ffmpegkit.**
-dontwarn org.ffmpeg.**
-keep class com.antonkarpenko.ffmpegkit.** { *; }