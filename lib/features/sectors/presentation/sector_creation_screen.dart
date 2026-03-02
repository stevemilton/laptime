import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../data/sector_repository.dart';

/// Full-screen route for creating a new sector definition.
class SectorCreationScreen extends ConsumerStatefulWidget {
  const SectorCreationScreen({super.key});

  @override
  ConsumerState<SectorCreationScreen> createState() =>
      _SectorCreationScreenState();
}

class _SectorCreationScreenState extends ConsumerState<SectorCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _startLatController = TextEditingController();
  final _startLngController = TextEditingController();
  final _endLatController = TextEditingController();
  final _endLngController = TextEditingController();

  String? _selectedCircuitId;
  List<LocalCircuit> _circuits = [];
  bool _isLoading = false;
  bool _circuitsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCircuits();
  }

  Future<void> _loadCircuits() async {
    final db = ref.read(databaseProvider);
    final circuits = await db.getAllCircuits();
    if (mounted) {
      setState(() {
        _circuits = circuits;
        _circuitsLoaded = true;
        if (circuits.isNotEmpty) {
          _selectedCircuitId = circuits.first.id;
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _startLatController.dispose();
    _startLngController.dispose();
    _endLatController.dispose();
    _endLngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Create Sector'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: !_circuitsLoaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Sector name
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Sector Name',
                      hintText: 'e.g. S1 - Copse',
                    ),
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Circuit picker
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCircuitId,
                    decoration: const InputDecoration(
                      labelText: 'Circuit',
                    ),
                    items: _circuits
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedCircuitId = v),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 24),

                  // Instructions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.purplePale,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          LucideIcons.info,
                          size: 18,
                          color: AppColors.purple,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Enter the GPS coordinates for the start and '
                            'end boundaries of this sector. These define '
                            'the gate lines used to compute sector times.',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.purpleMid),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Map placeholder
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppColors.ghost,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.map,
                            size: 32,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Map coming soon',
                            style: AppTypography.labelMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enter coordinates manually below',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Start Point
                  Text(
                    'START POINT',
                    style: AppTypography.sectionLabel,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _startLatController,
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            hintText: 'e.g. 52.0711',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          textInputAction: TextInputAction.next,
                          validator: _validateCoordinate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _startLngController,
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            hintText: 'e.g. -1.0168',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          textInputAction: TextInputAction.next,
                          validator: _validateCoordinate,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // End Point
                  Text(
                    'END POINT',
                    style: AppTypography.sectionLabel,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _endLatController,
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            hintText: 'e.g. 52.0685',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          textInputAction: TextInputAction.next,
                          validator: _validateCoordinate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _endLngController,
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            hintText: 'e.g. -1.0144',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          textInputAction: TextInputAction.done,
                          validator: _validateCoordinate,
                        ),
                      ),
                    ],
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
                        : const Text('Save Sector'),
                  ),
                ],
              ),
            ),
    );
  }

  String? _validateCoordinate(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Invalid number';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedCircuitId == null) return;

    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to create sectors.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = ref.read(databaseProvider);
      final repo = SectorRepository(db);

      await repo.createSector(
        circuitId: _selectedCircuitId!,
        createdBy: user.id,
        name: _nameController.text.trim(),
        startLat: double.parse(_startLatController.text.trim()),
        startLng: double.parse(_startLngController.text.trim()),
        endLat: double.parse(_endLatController.text.trim()),
        endLng: double.parse(_endLngController.text.trim()),
      );

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
