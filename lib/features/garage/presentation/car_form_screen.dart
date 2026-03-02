import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../data/car_repository.dart';

/// Form screen for creating or editing a car in the garage.
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
  String? _selectedClass;
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
    'Other',
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
    final db = ref.read(databaseProvider);
    final repo = CarRepository(db);
    final car = await repo.getCar(widget.carId!);
    if (car != null && mounted) {
      setState(() {
        _makeController.text = car.make;
        _modelController.text = car.model;
        _yearController.text = car.year?.toString() ?? '';
        _colourController.text = car.colour ?? '';
        _selectedClass = car.carClass;
      });
    }
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colourController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Car' : 'Add Car'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
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
            // Make
            TextFormField(
              controller: _makeController,
              decoration: const InputDecoration(
                labelText: 'Make',
                hintText: 'e.g. Porsche',
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
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'e.g. 911 GT3',
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
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Class
            DropdownButtonFormField<String>(
              initialValue: _selectedClass,
              decoration: const InputDecoration(
                labelText: 'Class',
              ),
              items: _carClasses
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedClass = v),
            ),
            const SizedBox(height: 16),

            // Colour
            TextFormField(
              controller: _colourController,
              decoration: const InputDecoration(
                labelText: 'Colour',
                hintText: 'e.g. Guards Red',
              ),
              textCapitalization: TextCapitalization.words,
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
                  : Text(_isEditing ? 'Save Changes' : 'Add Car'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final db = ref.read(databaseProvider);
      final repo = CarRepository(db);
      final year = int.tryParse(_yearController.text);
      final colour = _colourController.text.trim().isEmpty
          ? null
          : _colourController.text.trim();

      if (_isEditing) {
        await repo.updateCar(
          carId: widget.carId!,
          make: _makeController.text.trim(),
          model: _modelController.text.trim(),
          year: year,
          carClass: _selectedClass,
          colour: colour,
        );
      } else {
        final user = ref.read(currentUserProvider);
        if (user == null) return;

        await repo.createCar(
          userId: user.id,
          make: _makeController.text.trim(),
          model: _modelController.text.trim(),
          year: year,
          carClass: _selectedClass,
          colour: colour,
        );
      }

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

  Future<void> _deleteCar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Car'),
        content: const Text('Are you sure you want to remove this car from your garage?'),
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
      final db = ref.read(databaseProvider);
      final repo = CarRepository(db);
      await repo.deleteCar(widget.carId!);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }
}
