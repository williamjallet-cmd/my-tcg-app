-- ════════════════════════════════════════════════════════════════════════
--   BROKEMON — SUPPRESSIONS EN CASCADE + NETTOYAGE DES ORPHELINS
--
--   PROBLÈME
--   Deux suppressions ne nettoient rien derrière elles :
--
--   1. Supprimer une CARTE (removeCardFromCollection) efface la ligne de
--      `collection_cards`, mais laisse dans `user_collection_cards` une
--      ligne par joueur qui la possédait. Elles ne s'affichent plus nulle
--      part — mais elles sont toujours comptées par getMyOwnedCardCount,
--      donc le compteur « cartes possédées » du profil est faux.
--
--   2. Supprimer une COLLECTION efface `collections` et
--      `collection_members`, mais laisse `collection_cards`,
--      `user_collection_cards` et `collection_ratings` intacts.
--
--   POURQUOI CORRIGER EN SQL ET NON DANS L'APP
--   Un admin qui supprime une carte ne peut pas effacer les lignes des
--   AUTRES joueurs : les policies RLS le limitent aux siennes. Seule une
--   contrainte au niveau base nettoie pour tout le monde.
--
--   À coller EN ENTIER dans Supabase → SQL Editor → Run.
--   ⚠️ Les étapes 1 et 2 SUPPRIMENT des lignes déjà orphelines. Lance
--   d'abord l'étape 0 seule si tu veux voir l'ampleur avant d'agir.
-- ════════════════════════════════════════════════════════════════════════


-- ── ÉTAPE 0 : DIAGNOSTIC (ne modifie rien) ──────────────────────────────

SELECT 'cartes possédées sans collection' AS probleme, count(*) AS lignes
FROM public.user_collection_cards u
WHERE NOT EXISTS (
  SELECT 1 FROM public.collections c WHERE c.id = u.collection_id
)
UNION ALL
SELECT 'cartes possédées absentes du catalogue', count(*)
FROM public.user_collection_cards u
WHERE EXISTS (SELECT 1 FROM public.collections c WHERE c.id = u.collection_id)
  AND NOT EXISTS (
    SELECT 1 FROM public.collection_cards cc
    WHERE cc.collection_id = u.collection_id AND cc.card_id = u.card_id
  )
UNION ALL
SELECT 'entrées de catalogue sans collection', count(*)
FROM public.collection_cards cc
WHERE NOT EXISTS (
  SELECT 1 FROM public.collections c WHERE c.id = cc.collection_id
)
UNION ALL
SELECT 'membres sans collection', count(*)
FROM public.collection_members m
WHERE NOT EXISTS (
  SELECT 1 FROM public.collections c WHERE c.id = m.collection_id
);


-- ── ÉTAPE 1 : SUPPRIMER LES DOUBLONS DU CATALOGUE ───────────────────────
-- Nécessaire avant de poser la contrainte d'unicité de l'étape 3.
-- On garde la ligne la plus ancienne de chaque (collection, carte).

WITH ranked AS (
  SELECT ctid,
         ROW_NUMBER() OVER (
           PARTITION BY collection_id, card_id ORDER BY ctid
         ) AS rn
  FROM public.collection_cards
)
DELETE FROM public.collection_cards
WHERE ctid IN (SELECT ctid FROM ranked WHERE rn > 1);


-- ── ÉTAPE 2 : NETTOYER LES ORPHELINS EXISTANTS ──────────────────────────
-- Obligatoire : PostgreSQL refuse de créer une clé étrangère si des lignes
-- la violent déjà.

DELETE FROM public.user_collection_cards u
WHERE NOT EXISTS (
  SELECT 1 FROM public.collections c WHERE c.id = u.collection_id
);

DELETE FROM public.collection_cards cc
WHERE NOT EXISTS (
  SELECT 1 FROM public.collections c WHERE c.id = cc.collection_id
);

DELETE FROM public.collection_members m
WHERE NOT EXISTS (
  SELECT 1 FROM public.collections c WHERE c.id = m.collection_id
);

DELETE FROM public.collection_ratings r
WHERE NOT EXISTS (
  SELECT 1 FROM public.collections c WHERE c.id = r.collection_id
);

-- Cartes possédées dont la carte n'existe plus au catalogue
DELETE FROM public.user_collection_cards u
WHERE NOT EXISTS (
  SELECT 1 FROM public.collection_cards cc
  WHERE cc.collection_id = u.collection_id AND cc.card_id = u.card_id
);


-- ── ÉTAPE 3 : CLÉ D'UNICITÉ SUR LE CATALOGUE ────────────────────────────
-- Cible de la clé étrangère créée à l'étape 5.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'collection_cards_collection_card_unique'
  ) THEN
    ALTER TABLE public.collection_cards
      ADD CONSTRAINT collection_cards_collection_card_unique
      UNIQUE (collection_id, card_id);
    RAISE NOTICE '✅ Unicité posée sur collection_cards';
  END IF;
END $$;


-- ── ÉTAPE 4 : CASCADE DEPUIS LES COLLECTIONS ────────────────────────────
-- Supprimer une collection efface désormais tout ce qui en dépend.

DO $$
DECLARE
  t text;
  fk text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'collection_cards',
    'user_collection_cards',
    'collection_members',
    'collection_ratings'
  ] LOOP
    fk := t || '_collection_fk';
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = fk) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I '
        'FOREIGN KEY (collection_id) REFERENCES public.collections(id) '
        'ON DELETE CASCADE', t, fk
      );
      RAISE NOTICE '✅ Cascade collections → %', t;
    END IF;
  END LOOP;
END $$;


-- ── ÉTAPE 5 : CASCADE DEPUIS LE CATALOGUE ───────────────────────────────
-- Supprimer une carte du catalogue efface la ligne correspondante chez
-- TOUS les joueurs — y compris ceux que la RLS empêchait d'atteindre.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_collection_cards_catalogue_fk'
  ) THEN
    ALTER TABLE public.user_collection_cards
      ADD CONSTRAINT user_collection_cards_catalogue_fk
      FOREIGN KEY (collection_id, card_id)
      REFERENCES public.collection_cards(collection_id, card_id)
      ON DELETE CASCADE;
    RAISE NOTICE '✅ Cascade catalogue → cartes possédées';
  END IF;
END $$;


-- ── ÉTAPE 6 : VÉRIFICATION ──────────────────────────────────────────────
-- Toutes les lignes doivent maintenant afficher 0.
-- (Relance simplement l'étape 0.)

SELECT 'cartes possédées sans collection' AS probleme, count(*) AS lignes
FROM public.user_collection_cards u
WHERE NOT EXISTS (
  SELECT 1 FROM public.collections c WHERE c.id = u.collection_id
)
UNION ALL
SELECT 'cartes possédées absentes du catalogue', count(*)
FROM public.user_collection_cards u
WHERE NOT EXISTS (
  SELECT 1 FROM public.collection_cards cc
  WHERE cc.collection_id = u.collection_id AND cc.card_id = u.card_id
);