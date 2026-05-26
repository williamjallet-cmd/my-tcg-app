enum Rarity { common, uncommon, rare, epic, legendary }

enum CardEffect { none, holographic, shiny, negative }

class TextZone {
  String text;
  double x;
  double y;
  double fontSize;
  int color;
  String? fontFamily;

  TextZone({
    required this.text,
    this.x = 0,
    this.y = 0,
    this.fontSize = 16,
    this.color = 0xFFFFFFFF,
    this.fontFamily,
  });
}

class TCGCard {
  final String id;
  String name;
  String description;
  String type;
  int attack;
  int defense;
  Rarity rarity;
  CardEffect effect;
  String? imagePath;
  double imageX;
  double imageY;
  double imageScale;
  List<TextZone> textZones;

  TCGCard({
    required this.id,
    required this.name,
    this.description = '',
    this.type = 'Normal',
    this.attack = 0,
    this.defense = 0,
    this.rarity = Rarity.common,
    this.effect = CardEffect.none,
    this.imagePath,
    this.imageX = 0,
    this.imageY = 0,
    this.imageScale = 1.0,
    List<TextZone>? textZones,
  }) : textZones = textZones ?? [];

  String get rarityName {
    switch (rarity) {
      case Rarity.common:
        return 'Commun';
      case Rarity.uncommon:
        return 'Peu commun';
      case Rarity.rare:
        return 'Rare';
      case Rarity.epic:
        return 'Épique';
      case Rarity.legendary:
        return 'Légendaire';
    }
  }

  int get rarityColor {
    switch (rarity) {
      case Rarity.common:
        return 0xFF9E9E9E;
      case Rarity.uncommon:
        return 0xFF4CAF50;
      case Rarity.rare:
        return 0xFF2196F3;
      case Rarity.epic:
        return 0xFF9C27B0;
      case Rarity.legendary:
        return 0xFFFFD700;
    }
  }

  String get effectName {
    switch (effect) {
      case CardEffect.none:
        return 'Normal';
      case CardEffect.holographic:
        return 'Holographique';
      case CardEffect.shiny:
        return 'Brillant';
      case CardEffect.negative:
        return 'Négatif';
    }
  }
}
