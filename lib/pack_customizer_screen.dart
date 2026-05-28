// pack_customizer_screen.dart
// Écran réservé au propriétaire d'une collection pour personnaliser le pack :
// image centrale, titre et sous-titre. Aperçu en direct + sauvegarde Supabase.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'collection_service.dart';
import 'pack_opening_screen.dart';

class PackCustomizerScreen extends StatefulWidget {
  final CollectionModel collection;
  const PackCustomizerScreen({super.key, required this.collection});

  @override
  State<PackCustomizerScreen> createState() => _PackCustomizerScreenState();
}

class _PackCustomizerScreenState extends State<PackCustomizerScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  Uint8List? _imageBytes; // image fraîchement choisie (aperçu immédiat)
  String? _imageUrl; // image déjà enregistrée
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.collection;
    _titleCtrl = TextEditingController(
      text:
          (c.packTitle != null && c.packTitle!.isNotEmpty)
              ? c.packTitle!
              : c.name,
    );
    _subtitleCtrl = TextEditingController(
      text:
          (c.packSubtitle != null && c.packSubtitle!.isNotEmpty)
              ? c.packSubtitle!
              : 'Pack surprise',
    );
    _imageUrl = c.packImageUrl;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageBytes = bytes);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await CollectionService.instance.updateCollection(
        collectionId: widget.collection.id,
        packTitle: _titleCtrl.text.trim(),
        packSubtitle: _subtitleCtrl.text.trim(),
        packImageBytes: _imageBytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pack mis à jour !'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  bool get _hasImage =>
      _imageBytes != null || (_imageUrl != null && _imageUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080814),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1E),
        foregroundColor: Colors.white,
        title: const Text('Personnaliser le pack'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Center(
            child: PackPreview(
              title: _titleCtrl.text,
              subtitle: _subtitleCtrl.text,
              imageBytes: _imageBytes,
              imageUrl: _imageBytes == null ? _imageUrl : null,
              color: const Color(0xFF8A4DFF),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Aperçu en direct',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(
              Icons.add_photo_alternate_rounded,
              color: Colors.white70,
            ),
            label: Text(
              _hasImage ? 'Changer l\'image du pack' : 'Choisir une image',
              style: const TextStyle(color: Colors.white70),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _label('Titre du pack'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            maxLength: 18,
            style: const TextStyle(color: Colors.white),
            decoration: _deco('Ex. Booster'),
          ),
          const SizedBox(height: 8),
          _label('Sous-titre'),
          const SizedBox(height: 8),
          TextField(
            controller: _subtitleCtrl,
            onChanged: (_) => setState(() {}),
            maxLength: 24,
            style: const TextStyle(color: Colors.white),
            decoration: _deco('Ex. Pack surprise'),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child:
                    _saving
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Text(
                          'Enregistrer',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
  );

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
    ),
  );
}
