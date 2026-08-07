enum Rarity { common, uncommon, rare, epic, legendary }

enum CardEffect { none, holographic, shiny, negative }

// ════════════════════════════════════════════════════════════════════════════
//   DONNÉES DE JEU — inspirées des vrais TCG (PV, élément, attaques)
//
//   ⚠️ Tout est OPTIONNEL : une carte sans données de jeu reste parfaitement
//   valide et s'affiche comme avant. Les 44 cartes existantes n'ont rien à
//   migrer — les champs absents prennent simplement leur valeur par défaut.
// ════════════════════════════════════════════════════════════════════════════

/// Élément (type) d'une carte. `neutre` = aucun élément affiché.
enum CardElement { neutre, feu, eau, plante, electrik, glace, combat, psy }

extension CardElementInfo on CardElement {
  String get label {
    switch (this) {
      case CardElement.neutre:
        return 'Neutre';
      case CardElement.feu:
        return 'Feu';
      case CardElement.eau:
        return 'Eau';
      case CardElement.plante:
        return 'Plante';
      case CardElement.electrik:
        return 'Électrik';
      case CardElement.glace:
        return 'Glace';
      case CardElement.combat:
        return 'Combat';
      case CardElement.psy:
        return 'Psy';
    }
  }

  /// Symbole affiché sur la carte et dans le coût des attaques.
  String get symbol {
    switch (this) {
      case CardElement.neutre:
        return '⬤';
      case CardElement.feu:
        return '🔥';
      case CardElement.eau:
        return '💧';
      case CardElement.plante:
        return '🍃';
      case CardElement.electrik:
        return '⚡';
      case CardElement.glace:
        return '❄';
      case CardElement.combat:
        return '👊';
      case CardElement.psy:
        return '🔮';
    }
  }

  int get color {
    switch (this) {
      case CardElement.neutre:
        return 0xFFB0BEC5;
      case CardElement.feu:
        return 0xFFFF6B35;
      case CardElement.eau:
        return 0xFF2FA8FF;
      case CardElement.plante:
        return 0xFF3FD17A;
      case CardElement.electrik:
        return 0xFFFFC83D;
      case CardElement.glace:
        return 0xFF7FE7F5;
      case CardElement.combat:
        return 0xFFD1553F;
      case CardElement.psy:
        return 0xFFB45CFF;
    }
  }
}

/// Une attaque : un nom, un coût en énergies, des dégâts, un effet optionnel.
class CardAttack {
  String name;

  /// Nombre d'énergies requises (0 à 4), affichées avec le symbole de
  /// l'élément de la carte.
  int cost;
  int damage;

  /// Texte d'effet, facultatif (« Le tour suivant, … »).
  String effect;

  CardAttack({
    this.name = '',
    this.cost = 1,
    this.damage = 0,
    this.effect = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'cost': cost,
    'damage': damage,
    'effect': effect,
  };

  factory CardAttack.fromJson(Map<String, dynamic> j) => CardAttack(
    name: (j['name'] as String?) ?? '',
    cost: (j['cost'] as num?)?.toInt() ?? 1,
    damage: (j['damage'] as num?)?.toInt() ?? 0,
    effect: (j['effect'] as String?) ?? '',
  );

  CardAttack copy() =>
      CardAttack(name: name, cost: cost, damage: damage, effect: effect);
}

/// Regroupe toutes les données de jeu d'une carte.
/// `isEmpty` permet de savoir si la carte en possède ou non.
class CardStats {
  int? hp;
  CardElement element;
  CardElement? weakness;
  List<CardAttack> attacks;
  String flavorText;

  CardStats({
    this.hp,
    this.element = CardElement.neutre,
    this.weakness,
    List<CardAttack>? attacks,
    this.flavorText = '',
  }) : attacks = attacks ?? [];

  bool get isEmpty =>
      hp == null &&
      element == CardElement.neutre &&
      weakness == null &&
      attacks.isEmpty &&
      flavorText.isEmpty;

  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toJson() => {
    'hp': hp,
    'element': element.index,
    'weakness': weakness?.index,
    'attacks': attacks.map((a) => a.toJson()).toList(),
    'flavorText': flavorText,
  };

  /// Tolérant : un champ absent ou invalide retombe sur sa valeur par défaut,
  /// pour que les cartes créées avant cette fonctionnalité se chargent bien.
  factory CardStats.fromJson(Map<String, dynamic>? j) {
    if (j == null) return CardStats();
    CardElement? elementAt(Object? raw) {
      final i = (raw as num?)?.toInt();
      if (i == null || i < 0 || i >= CardElement.values.length) return null;
      return CardElement.values[i];
    }

    return CardStats(
      hp: (j['hp'] as num?)?.toInt(),
      element: elementAt(j['element']) ?? CardElement.neutre,
      weakness: elementAt(j['weakness']),
      attacks:
          ((j['attacks'] as List?) ?? [])
              .map((a) => CardAttack.fromJson(a as Map<String, dynamic>))
              .toList(),
      flavorText: (j['flavorText'] as String?) ?? '',
    );
  }

  CardStats copy() => CardStats(
    hp: hp,
    element: element,
    weakness: weakness,
    attacks: attacks.map((a) => a.copy()).toList(),
    flavorText: flavorText,
  );
}

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
