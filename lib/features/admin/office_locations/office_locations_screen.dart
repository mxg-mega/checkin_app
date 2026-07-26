// lib/features/admin/office_locations/office_locations_screen.dart

import 'package:checkin_app/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/location/location_service.dart';
import 'office_location_providers.dart';
import 'office_location_repository.dart';

class OfficeLocationsScreen extends ConsumerWidget {
  const OfficeLocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(officeLocationsProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(title: const Text('Office Locations')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(officeLocationsProvider),
        child: locationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Failed to load: $err')),
          data: (locations) {
            if (locations.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No office locations yet. Add one so employees can clock in/out.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              itemCount: locations.length,
              itemBuilder: (context, index) {
                final location = locations[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    leading: Icon(
                      Icons.location_on,
                      color: location.isActive ? Colors.green : Colors.grey,
                    ),
                    title: Text(location.name),
                    subtitle: Text(
                      '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}\n'
                      'Radius: ${location.radiusMeters}m'
                      '${location.isActive ? '' : ' · Inactive'}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) => _handleMenuAction(context, ref, value, location),
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(location.isActive ? 'Deactivate' : 'Activate'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, existing: null),
        icon: const Icon(Icons.add),
        label: const Text('Add Office'),
      ),
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context, WidgetRef ref, String action, OfficeLocation location) async {
    if (action == 'edit') {
      await _openEditor(context, ref, existing: location);
    } else if (action == 'toggle') {
      final repository = ref.read(officeLocationRepositoryProvider);
      final result = await repository.setActive(id: location.id, isActive: !location.isActive);
      ref.invalidate(officeLocationsProvider);
      if (context.mounted && result is OfficeLocationError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, {required OfficeLocation? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _OfficeLocationEditorSheet(existing: existing),
    );
    ref.invalidate(officeLocationsProvider);
  }
}

class _OfficeLocationEditorSheet extends ConsumerStatefulWidget {
  final OfficeLocation? existing;
  const _OfficeLocationEditorSheet({required this.existing});

  @override
  ConsumerState<_OfficeLocationEditorSheet> createState() => _OfficeLocationEditorSheetState();
}

class _OfficeLocationEditorSheetState extends ConsumerState<_OfficeLocationEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late final TextEditingController _radiusController;
  bool _fetchingLocation = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _latController = TextEditingController(text: e?.latitude.toString() ?? '');
    _lngController = TextEditingController(text: e?.longitude.toString() ?? '');
    _radiusController = TextEditingController(text: (e?.radiusMeters ?? 300).toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = ref.watch(officeLocationActionInProgressProvider);
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEditing ? 'Edit Office Location' : 'Add Office Location',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Office Name', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _fetchingLocation ? null : _useMyCurrentLocation,
                icon: _fetchingLocation
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
                label: Text(_fetchingLocation ? 'Getting location...' : 'Use My Current Location'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text(
                  'Stand at the office entrance and tap this to auto-fill the coordinates accurately.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      decoration: const InputDecoration(labelText: 'Latitude', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      validator: (v) => _validateCoordinate(v, min: -90, max: 90),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      decoration: const InputDecoration(labelText: 'Longitude', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      validator: (v) => _validateCoordinate(v, min: -180, max: 180),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _radiusController,
                decoration: const InputDecoration(
                  labelText: 'Geofence Radius (meters)',
                  border: OutlineInputBorder(),
                  helperText: 'Must be between 100 and 2000. You mentioned 250–500.',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a radius';
                  final parsed = int.tryParse(v.trim());
                  if (parsed == null) return 'Enter a whole number';
                  if (parsed < 100 || parsed > 2000) return 'Must be between 100 and 2000';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: inProgress ? null : _submit,
                  child: inProgress
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isEditing ? 'Save Changes' : 'Add Office'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateCoordinate(String? value, {required double min, required double max}) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number';
    if (parsed < min || parsed > max) return 'Must be between $min and $max';
    return null;
  }

  Future<void> _useMyCurrentLocation() async {
    setState(() => _fetchingLocation = true);
    final locationService = LocationService();
    final result = await locationService.getCurrentPosition();
    setState(() => _fetchingLocation = false);

    if (!mounted) return;

    switch (result) {
      case LocationSuccess(:final latitude, :final longitude):
        setState(() {
          _latController.text = latitude.toStringAsFixed(6);
          _lngController.text = longitude.toStringAsFixed(6);
        });
      case LocationFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
        );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(officeLocationActionInProgressProvider.notifier).state = true;
    final repository = ref.read(officeLocationRepositoryProvider);

    final name = _nameController.text;
    final lat = double.parse(_latController.text.trim());
    final lng = double.parse(_lngController.text.trim());
    final radius = int.parse(_radiusController.text.trim());

    final result = widget.existing == null
        ? await repository.create(name: name, latitude: lat, longitude: lng, radiusMeters: radius)
        : await repository.update(
            id: widget.existing!.id, name: name, latitude: lat, longitude: lng, radiusMeters: radius);

    ref.read(officeLocationActionInProgressProvider.notifier).state = false;
    if (!mounted) return;

    switch (result) {
      case OfficeLocationSuccess():
        Navigator.of(context).pop();
      case OfficeLocationError(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
        );
    }
  }
}
