import '../platform_detection.dart';

enum AppUiIdiom { iosMobile, macDesktop, tvosLeanback, material }

enum InterfaceStyle { automatic, apple, material }

class AppUiIdiomResolver {
  AppUiIdiomResolver._();

  static AppUiIdiom _current = _resolve(InterfaceStyle.automatic);
  static AppUiIdiom get current => _current;

  static void setOverride(InterfaceStyle style) {
    _current = _resolve(style);
  }

  static AppUiIdiom _resolve(InterfaceStyle style) {
    if (PlatformDetection.isAppleTV) return AppUiIdiom.tvosLeanback;
    if (PlatformDetection.isMacOS) return AppUiIdiom.macDesktop;
    switch (style) {
      case InterfaceStyle.material:
        return AppUiIdiom.material;
      case InterfaceStyle.apple:
        return PlatformDetection.isIOS || PlatformDetection.useMobileUi
            ? AppUiIdiom.iosMobile
            : AppUiIdiom.material;
      case InterfaceStyle.automatic:
        return PlatformDetection.isIOS
            ? AppUiIdiom.iosMobile
            : AppUiIdiom.material;
    }
  }

  static bool get isApple =>
      _current == AppUiIdiom.iosMobile || _current == AppUiIdiom.macDesktop;

  static bool styleAvailable() =>
      !(PlatformDetection.isAppleTV || PlatformDetection.isMacOS);
}
