import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/providers/sync_provider.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/widgets/section_header.dart';
import '../data/car_repository.dart';

/// Form screen for creating or editing a car/kart in the garage.
class CarFormScreen extends ConsumerStatefulWidget {
  const CarFormScreen({super.key, this.carId});

  final String? carId;

  @override
  ConsumerState<CarFormScreen> createState() => _CarFormScreenState();
}

class _CarFormScreenState extends ConsumerState<CarFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _colourController = TextEditingController();
  final _powerController = TextEditingController();
  final _weightController = TextEditingController();
  final _engineCapacityController = TextEditingController();
  final _modificationsController = TextEditingController();
  final _tyreSetupController = TextEditingController();
  String? _selectedClass;
  String? _selectedDrivetrain;
  String? _imageUrl;
  bool _isLoading = false;
  bool _isEditing = false;

  static const _carClasses = [
    'Road',
    'GT',
    'Touring',
    'Single Seater',
    'Sports Prototype',
    'Rally',
    'Drift',
    'Hillclimb',
    'Time Attack',
    'Autocross',
    'Kart',
    'Other',
  ];

  static const _drivetrains = [
    'FWD',
    'RWD',
    'AWD',
    '4WD',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.carId != null) {
      _isEditing = true;
      _loadCar();
    }
  }

  Future<void> _loadCar() async {
    try {
      final repo = ref.read(carRepositoryProvider);
      final car = await repo.getCar(widget.carId!);
      if (car != null && mounted) {
        setState(() {
          _makeController.text = car.make;
          _modelController.text = car.model;
          _yearController.text = car.year?.toString() ?? '';
          _colourController.text = car.colour ?? '';
          _powerController.text = car.powerHp?.toString() ?? '';
          _weightController.text = car.weightKg?.toString() ?? '';
          _engineCapacityController.text = car.engineCapacity ?? '';
          _modificationsController.text = car.modifications ?? '';
          _tyreSetupController.text = car.tyreSetup ?? '';
          _selectedClass = car.carClass;
          _selectedDrivetrain = car.drivetrain;
          _imageUrl = car.imageUrl;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load vehicle details. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colourController.dispose();
    _powerController.dispose();
    _weightController.dispose();
    _engineCapacityController.dispose();
    _modificationsController.dispose();
    _tyreSetupController.dispose();
    super.dispose();
  }

  bool get _isKart => _selectedClass == 'Kart';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Vehicle' : 'Add Vehicle'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/profile');
            }
          },
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(LucideIcons.trash2, color: AppColors.red),
              onPressed: _deleteCar,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Vehicle Photo ──
            _buildPhotoSection(),
            const SizedBox(height: 24),

            // ── Basic Info ──
            SectionHeader(title: 'BASIC INFO', padding: EdgeInsets.zero),
            const SizedBox(height: 12),

            // Class (moved to top so kart logic works)
            DropdownButtonFormField<String>(
              initialValue: _selectedClass,
              decoration: const InputDecoration(
                labelText: 'Class',
                prefixIcon: Icon(LucideIcons.flag, size: 18),
              ),
              items: _carClasses
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedClass = v),
            ),
            const SizedBox(height: 16),

            // Make
            TextFormField(
              controller: _makeController,
              decoration: InputDecoration(
                labelText: _isKart ? 'Chassis Make' : 'Make',
                hintText: _isKart ? 'e.g. Tony Kart, CRG' : 'e.g. Porsche',
                prefixIcon: Icon(
                  _isKart ? LucideIcons.gauge : LucideIcons.car,
                  size: 18,
                ),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Model
            TextFormField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: _isKart ? 'Chassis Model' : 'Model',
                hintText: _isKart ? 'e.g. Racer 401 RR' : 'e.g. 911 GT3',
                prefixIcon: const Icon(LucideIcons.tag, size: 18),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Year
            TextFormField(
              controller: _yearController,
              decoration: const InputDecoration(
                labelText: 'Year',
                hintText: 'e.g. 2024',
                prefixIcon: Icon(LucideIcons.calendar, size: 18),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Colour
            TextFormField(
              controller: _colourController,
              decoration: InputDecoration(
                labelText: 'Colour',
                hintText: _isKart ? 'e.g. Red / White' : 'e.g. Guards Red',
                prefixIcon: const Icon(LucideIcons.palette, size: 18),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 28),

            // ── Performance Specs ──
            SectionHeader(title: 'PERFORMANCE', padding: EdgeInsets.zero),
            const SizedBox(height: 12),

            // Engine capacity
            TextFormField(
              controller: _engineCapacityController,
              decoration: InputDecoration(
                labelText: _isKart ? 'Engine Package' : 'Engine',
                hintText: _isKart
                    ? 'e.g. Rotax 125, IAME X30'
                    : 'e.g. 4.0L flat-six',
                prefixIcon: const Icon(LucideIcons.zap, size: 18),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Power
            TextFormField(
              controller: _powerController,
              decoration: InputDecoration(
                labelText: 'Power (hp)',
                hintText: _isKart ? 'e.g. 34' : 'e.g. 502',
                prefixIcon: const Icon(LucideIcons.activity, size: 18),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Weight
            TextFormField(
              controller: _weightController,
              decoration: InputDecoration(
                labelText: _isKart ? 'Total Weight (kg)' : 'Kerb Weight (kg)',
                hintText: _isKart
                    ? 'e.g. 160 (kart + driver)'
                    : 'e.g. 1435',
                prefixIcon: const Icon(LucideIcons.scale, size: 18),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Drivetrain (hidden for karts - always RWD)
            if (!_isKart) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedDrivetrain,
                decoration: const InputDecoration(
                  labelText: 'Drivetrain',
                  prefixIcon: Icon(LucideIcons.settings2, size: 18),
                ),
                items: _drivetrains
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedDrivetrain = v),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 12),

            // ── Setup ──
            SectionHeader(title: 'SETUP', padding: EdgeInsets.zero),
            const SizedBox(height: 12),

            // Tyre setup
            TextFormField(
              controller: _tyreSetupController,
              decoration: InputDecoration(
                labelText: _isKart ? 'Tyre Setup' : 'Default Tyres',
                hintText: _isKart
                    ? 'e.g. MG Red, Mojo D5'
                    : 'e.g. Michelin Pilot Sport 4S',
                prefixIcon: const Icon(LucideIcons.circle, size: 18),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Modifications
            TextFormField(
              controller: _modificationsController,
              decoration: InputDecoration(
                labelText: _isKart ? 'Setup Notes' : 'Modifications',
                hintText: _isKart
                    ? 'e.g. Sprocket 11/80, seat position low'
                    : 'e.g. Coilovers, roll cage, bucket seats',
                prefixIcon: const Icon(LucideIcons.wrench, size: 18),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 32),

            // Save button
            FilledButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(LucideIcons.check, size: 18),
              label: Text(_isEditing ? 'Save Changes' : 'Add Vehicle'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    final hasImage = imageFileExists(_imageUrl);

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 200,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.ghost,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: hasImage ? Colors.transparent : AppColors.border,
            width: hasImage ? 0 : 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image(
                    image: _imageUrl!.startsWith('http')
                        ? NetworkImage(_imageUrl!) as ImageProvider
                        : FileImage(File(_imageUrl!)),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildPhotoPlaceholder(),
                  ),
                  // Dark overlay gradient at bottom
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.camera,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Change Photo',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _buildPhotoPlaceholder(),
      ),
    );
  }

  Widget _buildPhotoPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.purplePale,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            LucideIcons.camera,
            size: 24,
            color: AppColors.purple,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Add Vehicle Photo',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to take a photo or choose from gallery',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
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
              if (_imageUrl != null) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(LucideIcons.trash2, color: AppColors.red),
                  title: const Text('Remove Photo',
                      style: TextStyle(color: AppColors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _imageUrl = null);
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
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1200,
        imageQuality: 90,
      );

      if (picked == null) return;
      if (!mounted) return;

      // Crop the image
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        uiSettings: [
          IOSUiSettings(
            title: 'Crop Photo',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            aspectRatioPickerButtonHidden: false,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: true,
          ),
        ],
      );

      if (cropped == null) return;
      if (!mounted) return;

      // Copy to app documents directory for persistence
      final appDir = await getApplicationDocumentsDirectory();
      final carsDir = Directory(p.join(appDir.path, 'car_images'));
      if (!await carsDir.exists()) {
        await carsDir.create(recursive: true);
      }
      final ext = p.extension(cropped.path);
      final fileName = 'car_${DateTime.now().millisecondsSinceEpoch}$ext';
      final savedPath = p.join(carsDir.path, fileName);
      await File(cropped.path).copy(savedPath);

      if (mounted) {
        setState(() => _imageUrl = savedPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not load image. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(carRepositoryProvider);
      final year = int.tryParse(_yearController.text);
      final powerHp = int.tryParse(_powerController.text);
      final weightKg = int.tryParse(_weightController.text);
      final colour = _colourController.text.trim().isEmpty
          ? null
          : _colourController.text.trim();
      final engineCapacity = _engineCapacityController.text.trim().isEmpty
          ? null
          : _engineCapacityController.text.trim();
      final modifications = _modificationsController.text.trim().isEmpty
          ? null
          : _modificationsController.text.trim();
      final tyreSetup = _tyreSetupController.text.trim().isEmpty
          ? null
          : _tyreSetupController.text.trim();

      final formData = CarFormData(
        year: year,
        carClass: _selectedClass,
        colour: colour,
        imageUrl: _imageUrl,
        powerHp: powerHp,
        weightKg: weightKg,
        drivetrain: _isKart ? 'RWD' : _selectedDrivetrain,
        engineCapacity: engineCapacity,
        modifications: modifications,
        tyreSetup: tyreSetup,
      );

      if (_isEditing) {
        await repo.updateCar(
          carId: widget.carId!,
          make: _makeController.text.trim(),
          model: _modelController.text.trim(),
          data: formData,
        );
      } else {
        final user = ref.read(currentUserProvider);
        if (user == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Not signed in. Please restart the app.'),
                backgroundColor: AppColors.red,
              ),
            );
          }
          return;
        }

        await repo.createCar(
          userId: user.id,
          make: _makeController.text.trim(),
          model: _modelController.text.trim(),
          data: formData,
        );
      }

      // Trigger immediate sync so images upload right away.
      ref.read(syncServiceProvider).requestSync();

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/profile');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not save vehicle. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteCar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle'),
        content: const Text(
            'Are you sure you want to remove this vehicle from your garage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(carRepositoryProvider);
      await repo.deleteCar(widget.carId!);
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/profile');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete vehicle. Please try again.'), backgroundColor: AppColors.red),
        );
      }
    }
  }
}
