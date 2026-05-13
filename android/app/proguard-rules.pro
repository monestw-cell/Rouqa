# ============================================================================
# ProGuard Rules for رُقعة (Ruqa) Chess Analyzer
# ============================================================================
# Stockfish FFI native library keep rules
# Flutter framework rules
# AndroidX rules
# ============================================================================

# ── Stockfish native library ──────────────────────────────────────────────
# Keep all native method declarations for FFI
-keep class * { native <methods>; }

# Keep Stockfish package classes (stockfish_chess_engine / stockfish FFI)
-keep class com.stockfish.** { *; }
-keep class org.stockfish.** { *; }
-dontwarn com.stockfish.**
-dontwarn org.stockfish.**

# ── Flutter ──────────────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.**

# ── AndroidX ──────────────────────────────────────────────────────────────
-keep class androidx.core.** { *; }
-keep class androidx.appcompat.** { *; }
-dontwarn androidx.**

# ── SQLite (sqflite) ──────────────────────────────────────────────────────
-keep class io.sqlite4a.** { *; }
-dontwarn io.sqlite4a.**

# ── Dart FFI ──────────────────────────────────────────────────────────────
-keep class * implements java.lang.reflect.InvocationHandler { *; }

# ── General ──────────────────────────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
