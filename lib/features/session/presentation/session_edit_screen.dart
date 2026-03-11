import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../garage/data/car_repository.dart';
import '../data/session_repository.dart';

/// Post-session edit screen.
///
/// Allows the driver to tag a session with car, tyre info, track condition,
/// notes, and privacy setting after recording is complete.
class SessionEditScreen extends ConsumerStatefulWidget {
  const SessionEditScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionEditScreen> createState() => _SessionEditScreenState();
}

class _SessionEditScreenState extends ConsumerState<SessionEditScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form state
  final _circuitNameController = TextEditingController();
  String? _selectedCarId;
  String _trackCondition = 'dry';
  final _tyreBrandController = TextEditingController();
  final _tyreCompoundController = TextEditingController();
  final _tyreAgeLapsController = TextEditingController();
  final _setupNotesController = TextEditingController();
  final _sessionNotesController = TextEditingController();
  bool _isPublic = true;

  bool _isLoading = true;
  bool _isSaving = false;
  List<LocalCar> _cars = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _circuitNameController.dispose();
    _tyreBrandController.dispose();
    _tyreCompoundController.dispose();
    _tyreAgeLapsController.dispose();
    _setupNotesController.dispose();
    _sessionNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final repo = ref.read(sessionRepositoryProvider);
    final user = ref.read(currentUserProvider);

    final session = await repo.getSession(widget.sessionId);
    if (session == null || !mounted) return;

    // Load user's cars via repository
    final carRepo = ref.read(carRepositoryProvider);
    final cars = await carRepo.getUserCars(user?.id ?? '');

    if (!mounted) return;

    setState(() {
      _cars = cars;
      _circuitNameController.text = session.circuitName ?? '';
      _selectedCarId = session.carId;
      _trackCondition = session.trackCondition ?? 'dry';
      _tyreBrandController.text = session.tyreBrand ?? '';
      _tyreCompoundController.text = session.tyreCompound ?? '';
      _tyreAgeLapsController.text =
          session.tyreAgeLaps?.toString() ?? '';
      _setupNotesController.text = session.setupNotes ?? '';
      _sessionNotesController.text = session.sessionNotes ?? '';
      _isPublic = session.isPublic;
      _isLoading = false;
    });
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final repo = ref.read(sessionRepositoryProvider);

      final tyreAgeLaps = _tyreAgeLapsController.text.isNotEmpty
          ? int.tryParse(_tyreAgeLapsController.text)
          : null;

      await repo.updateSession(
        sessionId: widget.sessionId,
        circuitName: _circuitNameController.text.trim().isEmpty
            ? null
            : _circuitNameController.text.trim(),
        carId: _selectedCarId,
        trackCondition: _trackCondition,
        tyreBrand: _tyreBrandController.text.isNotEmpty
            ? _tyreBrandController.text
            : null,
        tyreCompound: _tyreCompoundController.text.isNotEmpty
            ? _tyreCompoundController.text
            : null,
        tyreAgeLaps: tyreAgeLaps,
        setupNotes: _setupNotesController.text.isNotEmpty
            ? _setupNotesController.text
            : null,
        sessionNotes: _sessionNotesController.text.isNotEmpty
            ? _sessionNotesController.text
            : null,
        isPublic: _isPublic,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session saved'),
            backgroundColor: AppColors.green,
          ),
        );
        if (Navigator.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/record');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/record');
            }
          },
        ),
        title: Text(
          'Edit Session',
          style: AppTypography.headlineSmall,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _isSaving ? null : _onSave,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.purple),
            )
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Circuit / Track name
          const SectionHeader(title: 'CIRCUIT / TRACK', padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          TextFormField(
            controller: _circuitNameController,
            decoration: const InputDecoration(
              labelText: 'Circuit Name',
              hintText: 'e.g. Brands Hatch, Silverstone',
              prefixIcon: Icon(LucideIcons.mapPin, size: 18),
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 24),

          // Car picker
          const SectionHeader(title: 'CAR', padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          _buildCarPicker(),
          const SizedBox(height: 24),

          // Track condition
          const SectionHeader(title: 'TRACK CONDITION', padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          TrackConditionSelector(
            selected: _trackCondition,
            onChanged: (value) => setState(() => _trackCondition = value),
          ),
          const SizedBox(height: 24),

          // Tyre info
          const SectionHeader(title: 'TYRE INFO', padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          _buildTyreFields(),
          const SizedBox(height: 24),

          // Setup notes
          const SectionHeader(title: 'SETUP NOTES', padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          _buildTextArea(
            controller: _setupNotesController,
            hintText: 'Suspension settings, pressures, wing angles...',
            maxLines: 4,
          ),
          const SizedBox(height: 24),

          // Session notes
          const SectionHeader(title: 'SESSION NOTES', padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          _buildTextArea(
            controller: _sessionNotesController,
            hintText: 'How the session went, conditions, observations...',
            maxLines: 4,
          ),
          const SizedBox(height: 24),

          // Privacy toggle
          _buildPrivacyToggle(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCarPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedCarId,
          isExpanded: true,
          icon: const Icon(LucideIcons.chevronDown, size: 18),
          hint: Text(
            'Select a car',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('No car selected'),
            ),
            ..._cars.map((car) {
              final label = car.year != null
                  ? '${car.year} ${car.make} ${car.model}'
                  : '${car.make} ${car.model}';
              return DropdownMenuItem<String?>(
                value: car.id,
                child: Text(label),
              );
            }),
          ],
          onChanged: (value) => setState(() => _selectedCarId = value),
        ),
      ),
    );
  }

  Widget _buildTyreFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _tyreBrandController,
                decoration: const InputDecoration(
                  labelText: 'Brand',
                  hintText: 'e.g. Pirelli',
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _tyreCompoundController,
                decoration: const InputDecoration(
                  labelText: 'Compound',
                  hintText: 'e.g. P Zero',
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _tyreAgeLapsController,
          decoration: const InputDecoration(
            labelText: 'Tyre age (laps)',
            hintText: 'Number of laps on these tyres',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }

  Widget _buildTextArea({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 4,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        alignLabelWithHint: true,
      ),
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
    );
  }

  Widget _buildPrivacyToggle() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            _isPublic ? LucideIcons.globe : LucideIcons.lock,
            size: 20,
            color: AppColors.purple,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPublic ? 'Public' : 'Private',
                  style: AppTypography.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  _isPublic
                      ? 'Visible on your profile and feed'
                      : 'Only you can see this session',
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isPublic,
            activeTrackColor: AppColors.purple,
            onChanged: (value) => setState(() => _isPublic = value),
          ),
        ],
      ),
    );
  }
}
