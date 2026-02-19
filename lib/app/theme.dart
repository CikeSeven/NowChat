import "package:flutter/material.dart";

/// MaterialTheme 类型定义。
class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff545a92),
      surfaceTint: Color(0xff545a92),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffdfe0ff),
      onPrimaryContainer: Color(0xff3c4279),
      secondary: Color(0xff5c5d72),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffe1e0f9),
      onSecondaryContainer: Color(0xff444559),
      tertiary: Color(0xff78536c),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffffd7ef),
      onTertiaryContainer: Color(0xff5e3c53),
      error: Color(0xffba1a1a),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffffdad6),
      onErrorContainer: Color(0xff93000a),
      surface: Color(0xfffbf8ff),
      onSurface: Color(0xff1b1b21),
      onSurfaceVariant: Color(0xff46464f),
      outline: Color(0xff777680),
      outlineVariant: Color(0xffc7c5d0),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff303036),
      inversePrimary: Color(0xffbdc2ff),
      primaryFixed: Color(0xffdfe0ff),
      onPrimaryFixed: Color(0xff0f154b),
      primaryFixedDim: Color(0xffbdc2ff),
      onPrimaryFixedVariant: Color(0xff3c4279),
      secondaryFixed: Color(0xffe1e0f9),
      onSecondaryFixed: Color(0xff181a2c),
      secondaryFixedDim: Color(0xffc4c4dd),
      onSecondaryFixedVariant: Color(0xff444559),
      tertiaryFixed: Color(0xffffd7ef),
      onTertiaryFixed: Color(0xff2e1126),
      tertiaryFixedDim: Color(0xffe7b9d6),
      onTertiaryFixedVariant: Color(0xff5e3c53),
      surfaceDim: Color(0xffdbd9e0),
      surfaceBright: Color(0xfffbf8ff),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfff5f2fa),
      surfaceContainer: Color(0xffefedf4),
      surfaceContainerHigh: Color(0xffeae7ef),
      surfaceContainerHighest: Color(0xffe4e1e9),
    );
  }

  ThemeData light() {
    return theme(lightScheme());
  }

  static ColorScheme lightMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff2b3167),
      surfaceTint: Color(0xff545a92),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xff6369a2),
      onPrimaryContainer: Color(0xffffffff),
      secondary: Color(0xff333548),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xff6a6b81),
      onSecondaryContainer: Color(0xffffffff),
      tertiary: Color(0xff4c2c42),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xff87627b),
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff740006),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffcf2c27),
      onErrorContainer: Color(0xffffffff),
      surface: Color(0xfffbf8ff),
      onSurface: Color(0xff101116),
      onSurfaceVariant: Color(0xff35353e),
      outline: Color(0xff52525b),
      outlineVariant: Color(0xff6d6c76),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff303036),
      inversePrimary: Color(0xffbdc2ff),
      primaryFixed: Color(0xff6369a2),
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: Color(0xff4a5088),
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: Color(0xff6a6b81),
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: Color(0xff525368),
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: Color(0xff87627b),
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: Color(0xff6d4a62),
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: Color(0xffc8c5cd),
      surfaceBright: Color(0xfffbf8ff),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfff5f2fa),
      surfaceContainer: Color(0xffeae7ef),
      surfaceContainerHigh: Color(0xffdedce3),
      surfaceContainerHighest: Color(0xffd3d0d8),
    );
  }

  ThemeData lightMediumContrast() {
    return theme(lightMediumContrastScheme());
  }

  static ColorScheme lightHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff21275c),
      surfaceTint: Color(0xff545a92),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xff3e447b),
      onPrimaryContainer: Color(0xffffffff),
      secondary: Color(0xff292b3d),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xff46485c),
      onSecondaryContainer: Color(0xffffffff),
      tertiary: Color(0xff402238),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xff603e56),
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff600004),
      onError: Color(0xffffffff),
      errorContainer: Color(0xff98000a),
      onErrorContainer: Color(0xffffffff),
      surface: Color(0xfffbf8ff),
      onSurface: Color(0xff000000),
      onSurfaceVariant: Color(0xff000000),
      outline: Color(0xff2b2b34),
      outlineVariant: Color(0xff484851),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff303036),
      inversePrimary: Color(0xffbdc2ff),
      primaryFixed: Color(0xff3e447b),
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: Color(0xff282e63),
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: Color(0xff46485c),
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: Color(0xff303144),
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: Color(0xff603e56),
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: Color(0xff48283f),
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: Color(0xffbab8bf),
      surfaceBright: Color(0xfffbf8ff),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfff2eff7),
      surfaceContainer: Color(0xffe4e1e9),
      surfaceContainerHigh: Color(0xffd6d3db),
      surfaceContainerHighest: Color(0xffc8c5cd),
    );
  }

  ThemeData lightHighContrast() {
    return theme(lightHighContrastScheme());
  }

  static ColorScheme darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xffbdc2ff),
      surfaceTint: Color(0xffbdc2ff),
      onPrimary: Color(0xff252b61),
      primaryContainer: Color(0xff3c4279),
      onPrimaryContainer: Color(0xffdfe0ff),
      secondary: Color(0xffc4c4dd),
      onSecondary: Color(0xff2d2f42),
      secondaryContainer: Color(0xff444559),
      onSecondaryContainer: Color(0xffe1e0f9),
      tertiary: Color(0xffe7b9d6),
      onTertiary: Color(0xff45263c),
      tertiaryContainer: Color(0xff5e3c53),
      onTertiaryContainer: Color(0xffffd7ef),
      error: Color(0xffffb4ab),
      onError: Color(0xff690005),
      errorContainer: Color(0xff93000a),
      onErrorContainer: Color(0xffffdad6),
      surface: Color(0xff131318),
      onSurface: Color(0xffe4e1e9),
      onSurfaceVariant: Color(0xffc7c5d0),
      outline: Color(0xff91909a),
      outlineVariant: Color(0xff46464f),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffe4e1e9),
      inversePrimary: Color(0xff545a92),
      primaryFixed: Color(0xffdfe0ff),
      onPrimaryFixed: Color(0xff0f154b),
      primaryFixedDim: Color(0xffbdc2ff),
      onPrimaryFixedVariant: Color(0xff3c4279),
      secondaryFixed: Color(0xffe1e0f9),
      onSecondaryFixed: Color(0xff181a2c),
      secondaryFixedDim: Color(0xffc4c4dd),
      onSecondaryFixedVariant: Color(0xff444559),
      tertiaryFixed: Color(0xffffd7ef),
      onTertiaryFixed: Color(0xff2e1126),
      tertiaryFixedDim: Color(0xffe7b9d6),
      onTertiaryFixedVariant: Color(0xff5e3c53),
      surfaceDim: Color(0xff131318),
      surfaceBright: Color(0xff39393f),
      surfaceContainerLowest: Color(0xff0d0e13),
      surfaceContainerLow: Color(0xff1b1b21),
      surfaceContainer: Color(0xff1f1f25),
      surfaceContainerHigh: Color(0xff29292f),
      surfaceContainerHighest: Color(0xff34343a),
    );
  }

  ThemeData dark() {
    return theme(darkScheme());
  }

  static ColorScheme darkMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xffd8daff),
      surfaceTint: Color(0xffbdc2ff),
      onPrimary: Color(0xff1a2055),
      primaryContainer: Color(0xff868cc8),
      onPrimaryContainer: Color(0xff000000),
      secondary: Color(0xffdadaf3),
      onSecondary: Color(0xff232437),
      secondaryContainer: Color(0xff8e8fa6),
      onSecondaryContainer: Color(0xff000000),
      tertiary: Color(0xfffecfec),
      onTertiary: Color(0xff391b31),
      tertiaryContainer: Color(0xffae859f),
      onTertiaryContainer: Color(0xff000000),
      error: Color(0xffffd2cc),
      onError: Color(0xff540003),
      errorContainer: Color(0xffff5449),
      onErrorContainer: Color(0xff000000),
      surface: Color(0xff131318),
      onSurface: Color(0xffffffff),
      onSurfaceVariant: Color(0xffdddbe6),
      outline: Color(0xffb2b1bb),
      outlineVariant: Color(0xff908f99),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffe4e1e9),
      inversePrimary: Color(0xff3d437a),
      primaryFixed: Color(0xffdfe0ff),
      onPrimaryFixed: Color(0xff030741),
      primaryFixedDim: Color(0xffbdc2ff),
      onPrimaryFixedVariant: Color(0xff2b3167),
      secondaryFixed: Color(0xffe1e0f9),
      onSecondaryFixed: Color(0xff0e1021),
      secondaryFixedDim: Color(0xffc4c4dd),
      onSecondaryFixedVariant: Color(0xff333548),
      tertiaryFixed: Color(0xffffd7ef),
      onTertiaryFixed: Color(0xff21071c),
      tertiaryFixedDim: Color(0xffe7b9d6),
      onTertiaryFixedVariant: Color(0xff4c2c42),
      surfaceDim: Color(0xff131318),
      surfaceBright: Color(0xff44444a),
      surfaceContainerLowest: Color(0xff07070c),
      surfaceContainerLow: Color(0xff1d1d23),
      surfaceContainer: Color(0xff27272d),
      surfaceContainerHigh: Color(0xff323238),
      surfaceContainerHighest: Color(0xff3d3d43),
    );
  }

  ThemeData darkMediumContrast() {
    return theme(darkMediumContrastScheme());
  }

  static ColorScheme darkHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xfff0eeff),
      surfaceTint: Color(0xffbdc2ff),
      onPrimary: Color(0xff000000),
      primaryContainer: Color(0xffb8befd),
      onPrimaryContainer: Color(0xff000238),
      secondary: Color(0xfff0eeff),
      onSecondary: Color(0xff000000),
      secondaryContainer: Color(0xffc0c1d9),
      onSecondaryContainer: Color(0xff080a1b),
      tertiary: Color(0xffffebf5),
      onTertiary: Color(0xff000000),
      tertiaryContainer: Color(0xffe3b6d2),
      onTertiaryContainer: Color(0xff1a0315),
      error: Color(0xffffece9),
      onError: Color(0xff000000),
      errorContainer: Color(0xffffaea4),
      onErrorContainer: Color(0xff220001),
      surface: Color(0xff131318),
      onSurface: Color(0xffffffff),
      onSurfaceVariant: Color(0xffffffff),
      outline: Color(0xfff1eefa),
      outlineVariant: Color(0xffc3c1cc),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffe4e1e9),
      inversePrimary: Color(0xff3d437a),
      primaryFixed: Color(0xffdfe0ff),
      onPrimaryFixed: Color(0xff000000),
      primaryFixedDim: Color(0xffbdc2ff),
      onPrimaryFixedVariant: Color(0xff030741),
      secondaryFixed: Color(0xffe1e0f9),
      onSecondaryFixed: Color(0xff000000),
      secondaryFixedDim: Color(0xffc4c4dd),
      onSecondaryFixedVariant: Color(0xff0e1021),
      tertiaryFixed: Color(0xffffd7ef),
      onTertiaryFixed: Color(0xff000000),
      tertiaryFixedDim: Color(0xffe7b9d6),
      onTertiaryFixedVariant: Color(0xff21071c),
      surfaceDim: Color(0xff131318),
      surfaceBright: Color(0xff504f56),
      surfaceContainerLowest: Color(0xff000000),
      surfaceContainerLow: Color(0xff1f1f25),
      surfaceContainer: Color(0xff303036),
      surfaceContainerHigh: Color(0xff3b3b41),
      surfaceContainerHighest: Color(0xff46464c),
    );
  }

  ThemeData darkHighContrast() {
    return theme(darkHighContrastScheme());
  }


  ThemeData theme(ColorScheme colorScheme) => ThemeData(
     useMaterial3: true,
     brightness: colorScheme.brightness,
     colorScheme: colorScheme,
     textTheme: textTheme.apply(
       bodyColor: colorScheme.onSurface,
       displayColor: colorScheme.onSurface,
     ),
     scaffoldBackgroundColor: colorScheme.surface,
     canvasColor: colorScheme.surface,
  );


  List<ExtendedColor> get extendedColors => [
  ];
}

/// ExtendedColor 类型定义。
class ExtendedColor {
  final Color seed, value;
  final ColorFamily light;
  final ColorFamily lightHighContrast;
  final ColorFamily lightMediumContrast;
  final ColorFamily dark;
  final ColorFamily darkHighContrast;
  final ColorFamily darkMediumContrast;

  const ExtendedColor({
    required this.seed,
    required this.value,
    required this.light,
    required this.lightHighContrast,
    required this.lightMediumContrast,
    required this.dark,
    required this.darkHighContrast,
    required this.darkMediumContrast,
  });
}

/// ColorFamily 类型定义。
class ColorFamily {
  const ColorFamily({
    required this.color,
    required this.onColor,
    required this.colorContainer,
    required this.onColorContainer,
  });

  final Color color;
  final Color onColor;
  final Color colorContainer;
  final Color onColorContainer;
}
