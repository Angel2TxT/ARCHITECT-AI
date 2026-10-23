import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class AttachmentPickResult {
  const AttachmentPickResult({required this.file, required this.name});

  final File file;
  final String name;
}

Future<AttachmentPickResult?> showAttachmentPickerSheet(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  return showModalBottomSheet<AttachmentPickResult>(
    context: context,
    backgroundColor: colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const AttachmentPickerSheet(),
  );
}

class AttachmentPickerSheet extends StatefulWidget {
  const AttachmentPickerSheet({super.key});

  @override
  State<AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<AttachmentPickerSheet> {
  static final _picker = ImagePicker();
  static bool _globalPicking = false;
  bool _localPicking = false;

  bool get _isBusy => _globalPicking || _localPicking;

  Future<void> _pickPhotos() async {
    if (_isBusy) return;
    setState(() => _localPicking = true);
    _globalPicking = true;

    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (image != null) {
        Navigator.pop(
          context,
          AttachmentPickResult(file: File(image.path), name: image.name),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('AttachmentPickerSheet: PlatformException ${e.code}: ${e.message}');
    } catch (e) {
      debugPrint('AttachmentPickerSheet: error picking photos: $e');
    } finally {
      _globalPicking = false;
      if (mounted) {
        setState(() => _localPicking = false);
      }
    }
  }

  Future<void> _pickCamera() async {
    if (_isBusy) return;
    setState(() => _localPicking = true);
    _globalPicking = true;

    try {
      final image = await _picker.pickImage(source: ImageSource.camera);
      if (!mounted) return;
      if (image != null) {
        Navigator.pop(
          context,
          AttachmentPickResult(file: File(image.path), name: image.name),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('AttachmentPickerSheet: PlatformException ${e.code}: ${e.message}');
    } catch (e) {
      debugPrint('AttachmentPickerSheet: error picking camera: $e');
    } finally {
      _globalPicking = false;
      if (mounted) {
        setState(() => _localPicking = false);
      }
    }
  }

  Future<void> _pickFiles() async {
    if (_isBusy) return;
    setState(() => _localPicking = true);
    _globalPicking = true;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'pdf',
          'doc',
          'docx',
          'dxf',
          'dwg',
        ],
      );
      if (!mounted) return;
      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        Navigator.pop(
          context,
          AttachmentPickResult(file: File(file.path!), name: file.name),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('AttachmentPickerSheet: PlatformException ${e.code}: ${e.message}');
    } catch (e) {
      debugPrint('AttachmentPickerSheet: error picking files: $e');
    } finally {
      _globalPicking = false;
      if (mounted) {
        setState(() => _localPicking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Row(
          children: [
            Expanded(
              child: _AttachmentOption(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Fotos',
                onTap: _isBusy ? null : _pickPhotos,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AttachmentOption(
                icon: Icons.photo_camera_outlined,
                label: 'Cámara',
                onTap: _isBusy ? null : _pickCamera,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AttachmentOption(
                icon: Icons.attach_file,
                label: 'Archivos',
                onTap: _isBusy ? null : _pickFiles,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tileColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : const Color(0xFFE9E9ED);

    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor: colorScheme.onSurface.withValues(alpha: 0.08),
        highlightColor: colorScheme.onSurface.withValues(alpha: 0.04),
        child: AspectRatio(
          aspectRatio: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colorScheme.onSurface, size: 32),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
