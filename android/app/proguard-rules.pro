# NODEX Enterprise HMS - ProGuard/R8 rules.
#
# Release builds are minified and resource-shrunk. These rules keep the members
# that reflection-based plugins and native bridges resolve at runtime, which R8
# cannot see from Dart call sites.

# --- Flutter engine and embedding -------------------------------------------
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- SQLCipher / SQLite (encrypted local operational projection) -------------
# net.zetetic is the SQLCipher Android binding used by sqlcipher_flutter_libs.
# Stripping it breaks database open with a native lookup failure at runtime.
-keep class net.zetetic.** { *; }
-keep class net.sqlcipher.** { *; }
-dontwarn net.zetetic.**
-dontwarn net.sqlcipher.**

# --- AndroidX Security / EncryptedSharedPreferences --------------------------
# Backs flutter_secure_storage, which holds the database encryption key.
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# --- Biometrics --------------------------------------------------------------
-keep class androidx.biometric.** { *; }

# --- WorkManager (background synchronization) --------------------------------
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }

# --- Kotlin coroutines -------------------------------------------------------
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**

# --- Diagnostics -------------------------------------------------------------
# Keep line numbers so a crash report from a ward device is actionable, while
# still obfuscating the original file names.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Annotations are used by plugin registration and serialization.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
