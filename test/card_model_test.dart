// card_model_test.dart
// ─────────────────────────────────────────────────────────────────────────
//   Tests des DONNÉES de carte — la partie où une régression coûte cher.
//
//   Contexte : des cartes ont déjà été perdues deux fois sur ce projet.
//   Le risque principal n'est pas visuel, il est ici : une carte enregistrée
//   avant l'ajout d'un champ doit continuer à se charger, et un aller-retour
//   d'enregistrement ne doit rien perdre en route.
//
//   Ces tests sont du Dart pur : ils tournent en une seconde, sans appareil.
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_app/card_layer.dart';
import 'package:tcg_app/card_model.dart';
import 'package:tcg_app/card_storage.dart';
import 'package:tcg_app/profile_service.dart';

void main() {
  group('CardStats — rétro-compatibilité', () {
    test('un JSON sans données de jeu donne des stats vides', () {
      // C'est le cas des 44 cartes existantes : elles n'ont pas de clé
      // « stats ». Elles doivent se charger sans erreur.
      final stats = CardStats.fromJson(null);
      expect(stats.isEmpty, isTrue);
      expect(stats.hp, isNull);
      expect(stats.element, CardElement.neutre);
      expect(stats.attacks, isEmpty);
    });

    test('un élément hors bornes ne fait pas planter le chargement', () {
      // Une valeur corrompue ou issue d'une version future ne doit jamais
      // rendre une carte illisible : on retombe sur la valeur par défaut.
      final stats = CardStats.fromJson({'element': 999, 'weakness': -3});
      expect(stats.element, CardElement.neutre);
      expect(stats.weakness, isNull);
    });

    test('les champs partiels sont tolérés', () {
      final stats = CardStats.fromJson({'hp': 90});
      expect(stats.hp, 90);
      expect(stats.flavorText, '');
      expect(stats.attacks, isEmpty);
    });
  });

  group('CardStats — aller-retour', () {
    test('toJson puis fromJson conserve tout', () {
      final original = CardStats(
        hp: 180,
        element: CardElement.feu,
        weakness: CardElement.eau,
        flavorText: 'Personne ne résiste à son gratin.',
        attacks: [
          CardAttack(name: 'Coup de louche', cost: 2, damage: 50),
          CardAttack(
            name: 'Flambée géante',
            cost: 3,
            damage: 120,
            effect: 'Défausse une énergie.',
          ),
        ],
      );

      final restored = CardStats.fromJson(original.toJson());

      expect(restored.hp, 180);
      expect(restored.element, CardElement.feu);
      expect(restored.weakness, CardElement.eau);
      expect(restored.flavorText, original.flavorText);
      expect(restored.attacks.length, 2);
      expect(restored.attacks[1].name, 'Flambée géante');
      expect(restored.attacks[1].damage, 120);
      expect(restored.attacks[1].effect, 'Défausse une énergie.');
    });

    test('copy() est indépendante de l\'originale', () {
      // L'éditeur continue de modifier ses stats après la sauvegarde :
      // la carte enregistrée ne doit pas suivre ces modifications.
      final original = CardStats(hp: 100, attacks: [CardAttack(name: 'Poing')]);
      final copie = original.copy();

      original.hp = 999;
      original.attacks[0].name = 'MODIFIÉ';

      expect(copie.hp, 100);
      expect(copie.attacks[0].name, 'Poing');
    });
  });

  group('SavedCard — sérialisation réseau', () {
    test('une carte SANS stats se recharge (format des 44 cartes)', () {
      // JSON minimal, tel qu'écrit avant l'ajout des données de jeu.
      final vieuxJson = {
        'id': 'abc',
        'name': 'Anto le Cuistot',
        'rarity': Rarity.legendary.index,
        'effect': CardEffect.none.index,
        'imageX': 0,
        'imageY': 0,
        'imageScale': 1.0,
        'extraImages': <dynamic>[],
        'textZones': <dynamic>[],
      };

      final card = CardStorage.fromJson(vieuxJson);

      expect(card.name, 'Anto le Cuistot');
      expect(card.rarity, Rarity.legendary);
      expect(card.stats.isEmpty, isTrue); // jamais null
    });

    test('les stats survivent à un aller-retour', () {
      final card = SavedCard(
        id: 'x1',
        name: 'Bruno Marié',
        rarity: Rarity.rare,
        stats: CardStats(
          hp: 120,
          element: CardElement.eau,
          attacks: [CardAttack(name: 'Vague', cost: 1, damage: 30)],
        ),
      );

      final restored = CardStorage.fromJson(CardStorage.toJson(card));

      expect(restored.stats.hp, 120);
      expect(restored.stats.element, CardElement.eau);
      expect(restored.stats.attacks.single.damage, 30);
    });
  });

  group('CardLayer — instantané et duplication', () {
    CardLayer sample() => CardLayer(
      id: 'layer-1',
      type: LayerType.text,
      role: LayerRole.cardName,
      x: 40,
      y: 90,
      text: 'Salut',
      rotation: 15,
    );

    test('snapshot() est une copie EXACTE (annulation)', () {
      // Une annulation doit remettre l'élément là où il était, à
      // l'identique — id et rôle compris.
      final l = sample();
      final s = l.snapshot();

      expect(s.id, l.id);
      expect(s.role, l.role);
      expect(s.x, l.x);
      expect(s.y, l.y);
      expect(s.rotation, l.rotation);
      expect(s.text, l.text);
    });

    test('snapshot() ne suit pas les modifications ultérieures', () {
      final l = sample();
      final s = l.snapshot();
      l.x = 999;
      l.text = 'MODIFIÉ';

      expect(s.x, 40);
      expect(s.text, 'Salut');
    });

    test('le verrou survit à un aller-retour JSON', () {
      final l = sample()..locked = true;
      final restored = CardLayer.fromJson(l.toJson());
      expect(restored.locked, isTrue);
    });

    test('une couche enregistrée avant le verrou se charge déverrouillée', () {
      // Cartes existantes : la clé « locked » est absente de leur JSON.
      final restored = CardLayer.fromJson({
        'id': 'vieux',
        'type': LayerType.text.index,
        'x': 10,
        'y': 20,
      });
      expect(restored.locked, isFalse);
      expect(restored.visible, isTrue);
    });

    test('clone() fabrique un DOUBLON distinct et décalé', () {
      // Ne pas confondre avec snapshot : le doublon doit coexister avec
      // l'original, donc nouvel id, position décalée, rôle neutralisé.
      final l = sample();
      final c = l.clone();

      expect(c.id, isNot(l.id));
      expect(c.x, l.x + 12);
      expect(c.role, LayerRole.normal);
    });
  });

  group('@pseudo — normalisation et validation', () {
    test('les majuscules sont converties, pas supprimées', () {
      // Le bug historique de la generation automatique : un regex [^a-z0-9]
      // applique avant le passage en minuscules mangeait les majuscules.
      expect(ProfileService.normalizeUsername('William'), 'william');
      expect(ProfileService.normalizeUsername('  @Willzer '), 'willzer');
    });

    test('les espaces deviennent des underscores', () {
      expect(ProfileService.normalizeUsername('will zer'), 'will_zer');
    });

    test('le format invalide est refusé avec un message', () {
      expect(ProfileService.validateUsername('ab'), isNotNull); // trop court
      expect(ProfileService.validateUsername('a' * 21), isNotNull); // trop long
      expect(ProfileService.validateUsername('will!'), isNotNull); // caractère
      expect(ProfileService.validateUsername(''), isNotNull);
    });

    test('un pseudo correct est accepté', () {
      expect(ProfileService.validateUsername('willzer'), isNull);
      expect(ProfileService.validateUsername('@Will_2'), isNull);
    });
  });
}
