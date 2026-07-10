// friends_screen.dart
// Refonte visuelle « Brokemon » — direction rétro-arcade premium.
// Logique & appels ProfileService inchangés ; seul l'habillage change.
//
// Dépendance requise (pubspec.yaml) :
//   google_fonts: ^6.2.1
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'profile_service.dart';

// ━━ TOKENS DESIGN ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _T {
  static const bg = Color(0xFF14101F); // aubergine nuit
  static const bgDeep = Color(0xFF0D0A16); // fond profond
  static const bgTop = Color(0xFF271C40); // halo haut du dégradé
  static const surface = Color(0xFF211A33);
  static const surface2 = Color(0xFF2B2240);
  static const gold = Color(0xFFFFC83D);
  static const goldDeep = Color(0xFFE0A91E);
  static const teal = Color(0xFF21E6C1);
  static const coral = Color(0xFFFF5D73);
  static const cream = Color(0xFFF6EEDD);

  static Color creamDim = cream.withValues(alpha: 0.62);
  static Color creamFaint = cream.withValues(alpha: 0.34);
  static Color line = cream.withValues(alpha: 0.10);

  // Titres / marquee arcade
  static TextStyle arcade(
    double size, {
    Color? color,
    double ls = 0.5,
    double height = 1.0,
  }) => GoogleFonts.lilitaOne(
    fontSize: size,
    color: color ?? cream,
    letterSpacing: ls,
    height: height,
  );

  // Corps
  static TextStyle bodyText(
    double size, {
    Color? color,
    FontWeight w = FontWeight.w600,
    double height = 1.0,
  }) => GoogleFonts.plusJakartaSans(
    fontSize: size,
    color: color ?? cream,
    fontWeight: w,
    height: height,
  );

  // Micro-labels pixel (jamais sur du texte courant)
  static TextStyle pixel(double size, {Color? color, double ls = 0.5}) =>
      GoogleFonts.silkscreen(
        fontSize: size,
        color: color ?? cream,
        letterSpacing: ls,
        height: 1.0,
      );

  static const radialBg = RadialGradient(
    center: Alignment(0, -1.15),
    radius: 1.4,
    colors: [bgTop, bg, bgDeep],
    stops: [0.0, 0.48, 1.0],
  );
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Friendship> _friends = [];
  List<Friendship> _pending = [];
  List<Friendship> _sent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ProfileService.instance.getFriends(),
        ProfileService.instance.getPendingRequests(),
        ProfileService.instance.getSentRequests(),
      ]);
      if (mounted) {
        setState(() {
          _friends = results[0];
          _pending = results[1];
          _sent = results[2];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(onAdded: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.bgDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: _T.radialBg),
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _header(),
                  Expanded(
                    child:
                        _loading
                            ? const Center(
                              child: CircularProgressIndicator(
                                color: _T.gold,
                                strokeWidth: 3,
                              ),
                            )
                            : TabBarView(
                              controller: _tabCtrl,
                              children: [
                                _friendsList(),
                                _pendingList(),
                                _sentList(),
                              ],
                            ),
                  ),
                ],
              ),
            ),
            // Scanlines CRT globales — très discrètes
            const Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _Scanlines())),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AMIS',
                    style: _T
                        .arcade(30, ls: 1)
                        .copyWith(
                          shadows: const [
                            Shadow(
                              color: Color(0x59000000),
                              offset: Offset(2, 3),
                            ),
                          ],
                        ),
                  ),
                ],
              ),
              const Spacer(),
              // Bouton + arcade doré (biseauté, s'enfonce au clic)
              _ArcadeButton(
                onTap: _showSearch,
                padding: const EdgeInsets.all(11),
                child: const Icon(
                  Icons.person_add_rounded,
                  color: Color(0xFF2A1C00),
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ArcadeTabs(
            controller: _tabCtrl,
            tabs: [
              _TabSpec('Amis (${_friends.length})'),
              _TabSpec('Reçues', badge: _pending.length),
              _TabSpec('Envoyées'),
            ],
          ),
        ],
      ),
    );
  }

  // ── Listes ─────────────────────────────────────────────────────────────────
  Widget _friendsList() {
    if (_friends.isEmpty) return _EmptyFriends(onAdd: _showSearch);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      itemCount: _friends.length,
      itemBuilder:
          (_, i) => _FriendTile(
            friendship: _friends[i],
            onRemove: () async {
              await ProfileService.instance.declineOrRemoveFriend(
                _friends[i].id,
              );
              _load();
            },
          ),
    );
  }

  Widget _pendingList() {
    if (_pending.isEmpty) {
      return const _EmptySimple(
        icon: Icons.mark_email_read_outlined,
        title: 'Aucune demande reçue',
        sub: 'Les demandes d\'amis apparaissent ici',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      itemCount: _pending.length,
      itemBuilder:
          (_, i) => _PendingTile(
            friendship: _pending[i],
            onAccept: () async {
              await ProfileService.instance.acceptFriendRequest(_pending[i].id);
              _load();
            },
            onDecline: () async {
              await ProfileService.instance.declineOrRemoveFriend(
                _pending[i].id,
              );
              _load();
            },
          ),
    );
  }

  Widget _sentList() {
    if (_sent.isEmpty) {
      return const _EmptySimple(
        icon: Icons.send_rounded,
        title: 'Aucune demande envoyée',
        sub: 'Tes demandes en attente apparaissent ici',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      itemCount: _sent.length,
      itemBuilder:
          (_, i) => _SentTile(
            friendship: _sent[i],
            onCancel: () async {
              await ProfileService.instance.declineOrRemoveFriend(_sent[i].id);
              _load();
            },
          ),
    );
  }
}

// ━━ ONGLETS ARCADE (indicateur glissant + glow) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _TabSpec {
  final String label;
  final int badge;
  _TabSpec(this.label, {this.badge = 0});
}

class _ArcadeTabs extends StatelessWidget {
  final TabController controller;
  final List<_TabSpec> tabs;
  const _ArcadeTabs({required this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration:
          Border(
            bottom: BorderSide(color: _T.line, width: 1.5),
          ).toBoxDecoration(),
      child: LayoutBuilder(
        builder: (_, c) {
          final slot = c.maxWidth / tabs.length;
          const indFrac = 0.46;
          final indW = slot * indFrac;
          return SizedBox(
            height: 46,
            child: Stack(
              children: [
                Row(
                  children: List.generate(tabs.length, (i) {
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => controller.animateTo(i),
                        child: AnimatedBuilder(
                          animation: controller.animation!,
                          builder: (_, __) {
                            final active =
                                (controller.animation!.value - i).abs() < 0.5;
                            return Center(child: _tabLabel(tabs[i], active));
                          },
                        ),
                      ),
                    );
                  }),
                ),
                AnimatedBuilder(
                  animation: controller.animation!,
                  builder: (_, __) {
                    final v = controller.animation!.value;
                    return Positioned(
                      bottom: 0,
                      left: slot * v + (slot - indW) / 2,
                      child: Container(
                        width: indW,
                        height: 3,
                        decoration: BoxDecoration(
                          color: _T.gold,
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: _T.gold.withValues(alpha: 0.7),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabLabel(_TabSpec t, bool active) {
    final color = active ? _T.cream : _T.creamFaint;
    final text = Text(
      t.label,
      style: _T.bodyText(14.5, color: color, w: FontWeight.w700),
    );
    if (t.badge <= 0) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 3, 6, 2),
          decoration: BoxDecoration(
            color: _T.coral,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: _T.coral.withValues(alpha: 0.45), blurRadius: 6),
            ],
          ),
          child: Text(
            '${t.badge}',
            style: _T.pixel(8, color: const Color(0xFF14101F)),
          ),
        ),
      ],
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}

// ━━ BOUTON ARCADE (relief biseauté, s'enfonce au clic) ━━━━━━━━━━━━━━━━━━━━━━━
class _ArcadeButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const _ArcadeButton({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
  });

  @override
  State<_ArcadeButton> createState() => _ArcadeButtonState();
}

class _ArcadeButtonState extends State<_ArcadeButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final btn = Transform.translate(
      offset: Offset(0, _down ? 5 : 0),
      child: Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE0A0), _T.gold, _T.goldDeep],
            stops: [0.0, 0.42, 1.0],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow:
              _down
                  ? [
                    const BoxShadow(color: _T.goldDeep, offset: Offset(0, 1)),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      offset: const Offset(0, 3),
                      blurRadius: 8,
                    ),
                  ]
                  : [
                    const BoxShadow(color: _T.goldDeep, offset: Offset(0, 6)),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      offset: const Offset(0, 12),
                      blurRadius: 22,
                    ),
                  ],
        ),
        child: Stack(
          children: [
            // gleam (reflet biseau supérieur)
            Positioned(
              top: 1,
              left: 10,
              right: 10,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.6),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            DefaultTextStyle.merge(
              style: GoogleFonts.lilitaOne(
                color: const Color(0xFF2A1C00),
                letterSpacing: 0.5,
              ),
              child: Center(child: widget.child),
            ),
          ],
        ),
      ),
    );
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: btn,
    );
  }
}

// ━━ BADGE PIXEL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _PixelBadge extends StatelessWidget {
  final String label;
  const _PixelBadge(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: _T.cream, width: 1.5),
    ),
    child: Text(label.toUpperCase(), style: _T.pixel(8.5, color: _T.cream)),
  );
}

// ━━ TUILES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BoxDecoration _surfaceCard({Color? border}) => BoxDecoration(
  color: _T.surface,
  borderRadius: BorderRadius.circular(16),
  border: border != null ? Border.all(color: border, width: 1.5) : null,
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ],
);

class _FriendTile extends StatelessWidget {
  final Friendship friendship;
  final VoidCallback onRemove;
  const _FriendTile({required this.friendship, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
    decoration: _surfaceCard(),
    child: Row(
      children: [
        _Avatar(profile: friendship.user),
        const SizedBox(width: 12),
        Expanded(child: _NameBlock(friendship.user)),
        PopupMenuButton<String>(
          color: _T.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          icon: Icon(Icons.more_vert, color: _T.creamFaint),
          onSelected: (v) {
            if (v == 'remove') onRemove();
          },
          itemBuilder:
              (_) => [
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_remove,
                        color: _T.coral,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Retirer',
                        style: _T.bodyText(
                          14,
                          color: _T.coral,
                          w: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
        ),
      ],
    ),
  );
}

class _PendingTile extends StatelessWidget {
  final Friendship friendship;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _PendingTile({
    required this.friendship,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: _surfaceCard(border: _T.gold.withValues(alpha: 0.38)).copyWith(
      boxShadow: [
        BoxShadow(
          color: _T.gold.withValues(alpha: 0.12),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        _Avatar(profile: friendship.user),
        const SizedBox(width: 12),
        Expanded(child: _NameBlock(friendship.user)),
        // Refuser
        _CircleBtn(
          icon: Icons.close,
          iconColor: _T.coral,
          bg: _T.coral.withValues(alpha: 0.15),
          onTap: onDecline,
        ),
        const SizedBox(width: 8),
        // Accepter (or arcade)
        _CircleBtn(
          icon: Icons.check,
          iconColor: const Color(0xFF2A1C00),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE0A0), _T.goldDeep],
          ),
          glow: _T.gold.withValues(alpha: 0.5),
          onTap: onAccept,
        ),
      ],
    ),
  );
}

class _SentTile extends StatelessWidget {
  final Friendship friendship;
  final VoidCallback onCancel;
  const _SentTile({required this.friendship, required this.onCancel});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    decoration: _surfaceCard(),
    child: Row(
      children: [
        _Avatar(profile: friendship.user),
        const SizedBox(width: 12),
        Expanded(child: _NameBlock(friendship.user)),
        const _PixelBadge('En attente'),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onCancel,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.close, size: 18, color: _T.creamFaint),
          ),
        ),
      ],
    ),
  );
}

class _NameBlock extends StatelessWidget {
  final UserProfile user;
  const _NameBlock(this.user);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        user.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _T
            .arcade(16)
            .copyWith(
              shadows: const [
                Shadow(color: Color(0x73000000), offset: Offset(0, 1.5)),
              ],
            ),
      ),
      const SizedBox(height: 2),
      Text(
        '@${user.username}'.toUpperCase(),
        style: _T.pixel(8, color: _T.creamFaint, ls: 0.5),
      ),
    ],
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color? bg;
  final Gradient? gradient;
  final Color? glow;
  final VoidCallback onTap;
  const _CircleBtn({
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.bg,
    this.gradient,
    this.glow,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        shape: BoxShape.circle,
        boxShadow:
            glow != null ? [BoxShadow(color: glow!, blurRadius: 12)] : null,
      ),
      child: Icon(icon, color: iconColor, size: 20),
    ),
  );
}

// ━━ AVATAR ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _Avatar extends StatelessWidget {
  final UserProfile profile;
  const _Avatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _T.gold.withValues(alpha: 0.30), width: 1.5),
      ),
      child: _inner(),
    );
  }

  Widget _inner() {
    if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
      if (profile.avatarUrl!.startsWith('preset:')) {
        final emoji = profile.avatarUrl!.replaceFirst('preset:', '');
        return CircleAvatar(
          radius: 22,
          backgroundColor: _T.surface2,
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        );
      }
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(profile.avatarUrl!),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: _T.surface2,
      child: Text(
        profile.displayName.isNotEmpty
            ? profile.displayName[0].toUpperCase()
            : '?',
        style: _T.arcade(18, color: _T.gold),
      ),
    );
  }
}

// ━━ ÉTAT VIDE — AMIS (emblème + rayons + CTA) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _EmptyFriends extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyFriends({required this.onAdd});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _Emblem(),
        const SizedBox(height: 26),
        Text('PAS ENCORE D\'AMIS', style: _T.arcade(22, ls: 0.8)),
        const SizedBox(height: 10),
        Text(
          'Invite des dresseurs pour échanger\ndes cartes et ouvrir des packs ensemble !',
          textAlign: TextAlign.center,
          style: _T.bodyText(
            13.5,
            color: _T.creamDim,
            w: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        _ArcadeButton(
          onTap: onAdd,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_add_rounded,
                color: Color(0xFF2A1C00),
                size: 19,
              ),
              const SizedBox(width: 10),
              Text(
                'AJOUTER UN AMI',
                style: GoogleFonts.lilitaOne(
                  fontSize: 16,
                  color: const Color(0xFF2A1C00),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Emblem extends StatefulWidget {
  const _Emblem();
  @override
  State<_Emblem> createState() => _EmblemState();
}

class _EmblemState extends State<_Emblem> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rayons dorés qui tournent (rayspin) — masqués en radial
          RotationTransition(
            turns: _spin,
            child: const SizedBox(
              width: 132,
              height: 132,
              child: CustomPaint(painter: _RayBurst()),
            ),
          ),
          // Cercles décoratifs concentriques
          _ring(108, 0.15),
          _ring(80, 0.25),
          // Centre or pulsé
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_T.gold, Color(0xFFC9920E)],
              ),
              boxShadow: [
                BoxShadow(
                  color: _T.gold.withValues(alpha: 0.5),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.people_rounded,
              color: Color(0xFF2A1C00),
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double d, double alpha) => Container(
    width: d,
    height: d,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: _T.gold.withValues(alpha: alpha), width: 1),
    ),
  );
}

class _RayBurst extends CustomPainter {
  const _RayBurst();
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()..color = _T.gold.withValues(alpha: 0.18);
    const rays = 20;
    for (int i = 0; i < rays; i++) {
      final a0 = (i / rays) * 2 * math.pi;
      final a1 = a0 + (2 * math.pi / rays) * 0.42;
      final path =
          Path()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx + r * math.cos(a0), c.dy + r * math.sin(a0))
            ..lineTo(c.dx + r * math.cos(a1), c.dy + r * math.sin(a1))
            ..close();
      canvas.drawPath(path, paint);
    }
    // Masque radial : fond opaque au centre, fondu vers l'extérieur
    canvas.drawCircle(
      c,
      r * 0.20,
      Paint()
        ..shader = RadialGradient(
          colors: [_T.bg, _T.bg.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.20)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ━━ ÉTAT VIDE — SIMPLE (reçues / envoyées) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _EmptySimple extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _EmptySimple({
    required this.icon,
    required this.title,
    required this.sub,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 50, color: _T.cream.withValues(alpha: 0.12)),
        const SizedBox(height: 16),
        Text(
          title.toUpperCase(),
          style: _T.arcade(16, color: _T.creamDim, ls: 0.6),
        ),
        const SizedBox(height: 8),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: _T.bodyText(12.5, color: _T.creamFaint, w: FontWeight.w600),
        ),
      ],
    ),
  );
}

// ━━ SCANLINES CRT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _Scanlines extends CustomPainter {
  const _Scanlines();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: 0.05);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ━━ SEARCH SHEET ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _SearchSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _SearchSheet({required this.onAdded});
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctrl = TextEditingController();
  List<UserProfile> _results = [];
  bool _searching = false;
  final Set<String> _sent = {};

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await ProfileService.instance.searchUsers(q);
      if (mounted) setState(() => _results = res);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(UserProfile user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ProfileService.instance.sendFriendRequest(user.id);
      if (!mounted) return;
      setState(() => _sent.add(user.id));
      widget.onAdded();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Demande envoyée à ${user.displayName} !',
            style: _T.bodyText(13, w: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF0F5B43),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$e', style: _T.bodyText(13, w: FontWeight.w700)),
          backgroundColor: const Color(0xFF7A1E2B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        left: 20,
        right: 20,
        top: 14,
      ),
      decoration: const BoxDecoration(
        color: _T.bgDeep,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF2B2240), width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _T.cream.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text('AJOUTER UN AMI', style: _T.arcade(20, ls: 0.6)),
          const SizedBox(height: 4),
          Text(
            'RECHERCHE PAR NOM OU @USERNAME',
            style: _T.pixel(8, color: _T.teal, ls: 1.2),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: _T.bodyText(15, w: FontWeight.w600),
            cursorColor: _T.gold,
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Rechercher…',
              hintStyle: _T.bodyText(
                15,
                color: _T.cream.withValues(alpha: 0.3),
                w: FontWeight.w500,
              ),
              prefixIcon: Icon(Icons.search, color: _T.creamFaint),
              filled: true,
              fillColor: _T.cream.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _T.line, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _T.gold, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: _T.gold, strokeWidth: 3),
            )
          else
            ..._results.map(
              (u) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  color: _T.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _T.line, width: 1.5),
                ),
                child: Row(
                  children: [
                    _Avatar(profile: u),
                    const SizedBox(width: 12),
                    Expanded(child: _NameBlock(u)),
                    if (_sent.contains(u.id))
                      const Icon(Icons.check_circle, color: _T.teal)
                    else
                      _ArcadeButton(
                        onTap: () => _add(u),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        child: Text(
                          'AJOUTER',
                          style: GoogleFonts.lilitaOne(
                            fontSize: 12.5,
                            color: const Color(0xFF2A1C00),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
