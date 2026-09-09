import 'package:flutter/painting.dart';

/// Corner radii from the handoff (UX-001 "Shape").
abstract final class SparklingShapes {
  /// Phone screen corners (device frame).
  static const double phone = 36;

  /// Hero / feature cards.
  static const double hero = 28;

  /// Standard cards.
  static const double card = 22;

  /// Admin cards.
  static const double adminCard = 24;

  /// Admin frame.
  static const double adminFrame = 20;

  /// List tiles, input fields, date chips.
  static const double tile = 18;

  /// Icon tiles (44px avatar / icon buttons).
  static const double iconTile = 16;

  /// Small tonal icon tiles inside quick-action cards.
  static const double iconTileSmall = 14;

  /// Dialogs.
  static const double dialog = 28;

  /// Bottom sheet top corners.
  static const double sheet = 32;

  /// Full pill.
  static const double pill = 100;

  /// Extended FAB.
  static const double fab = 20;

  /// Payment card plate 44×32 r8.
  static const double plate = 8;

  /// Navigation indicator pill.
  static const Size navIndicator = Size(56, 30);

  static BorderRadius radius(double r) => BorderRadius.circular(r);

  static const BorderRadius heroRadius = BorderRadius.all(
    Radius.circular(hero),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius tileRadius = BorderRadius.all(
    Radius.circular(tile),
  );
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );

  static const RoundedRectangleBorder heroShape = RoundedRectangleBorder(
    borderRadius: heroRadius,
  );
  static const RoundedRectangleBorder cardShape = RoundedRectangleBorder(
    borderRadius: cardRadius,
  );
  static const RoundedRectangleBorder tileShape = RoundedRectangleBorder(
    borderRadius: tileRadius,
  );
  static const StadiumBorder pillShape = StadiumBorder();
  static const RoundedRectangleBorder sheetShape = RoundedRectangleBorder(
    borderRadius: sheetRadius,
  );
  static const RoundedRectangleBorder dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(dialog)),
  );
}
