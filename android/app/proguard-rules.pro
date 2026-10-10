# F-Droid: Flutter's embedding contains two Google Play Store wrappers
# (FlutterPlayStoreSplitApplication, PlayStoreDeferredComponentManager) that this app never uses.
# They reference Google Play Core classes, which F-Droid's scanner rejects.
#
# Everything EXCEPT those two wrappers is kept untouched (no shrinking, renaming or optimizing),
# so libmpv / media_kit JNI lookups behave exactly as with R8 turned off. R8 only drops the wrappers.
-dontobfuscate
-dontoptimize
-keep class !io.flutter.embedding.engine.deferredcomponents.**, !io.flutter.embedding.android.FlutterPlayStoreSplitApplication, ** { *; }
-keepattributes *
-dontwarn com.google.android.play.core.**
-ignorewarnings
