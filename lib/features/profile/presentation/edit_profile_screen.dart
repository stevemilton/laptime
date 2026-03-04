import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/providers/sync_provider.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/profile_repository.dart';

/// Edit profile screen for updating display name, handle, and avatar.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _handleController = TextEditingController();
  bool _isLoading = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final db = ref.read(databaseProvider);
    final client = ref.read(supabaseClientProvider);
    final repo = ProfileRepository(db, client);
    final profile = await repo.getProfile(user.id);

    if (profile != null && mounted) {
      setState(() {
        _nameController.text = profile.displayName;
        _handleController.text = profile.handle ?? '';
        _avatarUrl = profile.avatarUrl;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Avatar with working photo picker
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  _buildAvatar(),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.purple,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2),
                      ),
                      child: const Icon(
                        LucideIcons.camera,
                        size: 14,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Tap to change photo',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Display name
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              prefixIcon: Icon(LucideIcons.user, size: 18),
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // Handle
          TextFormField(
            controller: _handleController,
            decoration: const InputDecoration(
              labelText: 'Handle',
              prefixIcon: Icon(LucideIcons.atSign, size: 18),
              hintText: 'e.g. fastdriver42',
            ),
            autocorrect: false,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 32),

          // Save button
          FilledButton(
            onPressed: _isLoading ? null : _save,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  /// Check whether a local image file actually exists on disk.
  bool _imageFileExists(String? url) {
    if (url == null || url.isEmpty) return false;
    if (url.startsWith('http')) return true;
    return File(url).existsSync();
  }

  Widget _buildAvatar() {
    if (_imageFileExists(_avatarUrl)) {
      final isLocal = !_avatarUrl!.startsWith('http');
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.purpleLight,
          image: DecorationImage(
            image: isLocal
                ? FileImage(File(_avatarUrl!)) as ImageProvider
                : NetworkImage(_avatarUrl!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Fallback with initials
    final name = _nameController.text;
    String? initials;
    if (name.isNotEmpty) {
      final parts = name.split(' ');
      if (parts.length >= 2) {
        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else {
        initials = name[0].toUpperCase();
      }
    }

    return AppAvatar.xl(initials: initials);
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading:
                    const Icon(LucideIcons.camera, color: AppColors.purple),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading:
                    const Icon(LucideIcons.image, color: AppColors.purple),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              if (_avatarUrl != null) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(LucideIcons.trash2, color: AppColors.red),
                  title: const Text('Remove Photo',
                      style: TextStyle(color: AppColors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _avatarUrl = null);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      debugPrint('[Avatar] Picking image from $source');
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 90,
      );

      if (picked == null) {
        debugPrint('[Avatar] Picker returned null (user cancelled or permission denied)');
        return;
      }
      if (!mounted) return;
      debugPrint('[Avatar] Picked: ${picked.path}');

      // Crop to square for avatar
      debugPrint('[Avatar] Opening cropper...');
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          IOSUiSettings(
            title: 'Crop Photo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (cropped == null) {
        debugPrint('[Avatar] Cropper returned null (user cancelled)');
        return;
      }
      if (!mounted) return;
      debugPrint('[Avatar] Cropped: ${cropped.path}');

      // Copy to app documents directory for persistence
      final appDir = await getApplicationDocumentsDirectory();
      final avatarsDir = Directory(path.join(appDir.path, 'avatars'));
      if (!await avatarsDir.exists()) {
        await avatarsDir.create(recursive: true);
      }
      final ext = path.extension(cropped.path);
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}$ext';
      final savedPath = path.join(avatarsDir.path, fileName);
      await File(cropped.path).copy(savedPath);
      debugPrint('[Avatar] Saved to: $savedPath (exists: ${File(savedPath).existsSync()})');

      if (mounted) {
        setState(() => _avatarUrl = savedPath);
        debugPrint('[Avatar] State updated with avatarUrl: $savedPath');
      }
    } catch (e, stack) {
      debugPrint('[Avatar] ERROR: $e');
      debugPrint('[Avatar] STACK: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load image: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final db = ref.read(databaseProvider);
      final client = ref.read(supabaseClientProvider);
      final repo = ProfileRepository(db, client);

      await repo.updateProfile(
        userId: user.id,
        displayName: _nameController.text.trim(),
        handle: _handleController.text.trim().isEmpty
            ? null
            : _handleController.text.trim(),
        avatarUrl: _avatarUrl,
      );

      // Trigger immediate sync so avatar uploads right away.
      ref.read(syncServiceProvider).requestSync();

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
