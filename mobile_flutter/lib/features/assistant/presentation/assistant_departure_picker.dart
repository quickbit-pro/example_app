import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_localizations.dart';
import '../data/assistant_location.dart';
import '../domain/assistant_departure.dart';

/// Compact, visible trip origin. This widget never requests location on load.
class AssistantDeparturePicker extends ConsumerStatefulWidget {
  const AssistantDeparturePicker({
    required this.departure,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final AssistantDeparture? departure;
  final ValueChanged<AssistantDeparture?> onChanged;
  final bool enabled;

  @override
  ConsumerState<AssistantDeparturePicker> createState() =>
      _AssistantDeparturePickerState();
}

class _AssistantDeparturePickerState
    extends ConsumerState<AssistantDeparturePicker> {
  DialogRoute<_Selection>? _route;
  NavigatorState? _navigator;
  VoidCallback? _cancelDialog;

  Future<void> _edit() async {
    if (_route != null) return;
    final navigator = _navigator = Navigator.of(context);
    final service = ref.read(assistantLocationProvider);
    final route = _route = DialogRoute<_Selection>(
      context: context,
      builder: (_) => _DepartureDialog(
        departure: widget.departure,
        service: service,
        registerCancellation: (cancel) => _cancelDialog = cancel,
      ),
    );
    final selection = await navigator.push(route);
    if (!mounted || _route != route) return;
    _route = null;
    _cancelDialog = null;
    if (selection != null) widget.onChanged(selection.departure);
  }

  @override
  void dispose() {
    // A dialog is a separate route: changing the account-scoped parent key
    // must dismiss it as well as abandoning any GPS result. The text
    // controller is disposed with the route; notifying it here can hit an
    // inactive EditableText during account teardown.
    _cancelDialog?.call();
    final route = _route;
    final navigator = _navigator;
    _route = null;
    if (route != null) {
      scheduleMicrotask(() {
        if (navigator?.mounted == true && route.isActive) {
          navigator!.removeRoute(route);
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('assistant-departure'),
          onPressed: widget.enabled ? _edit : null,
          icon: const Icon(Icons.flight_takeoff, size: 18),
          label: Text(
            widget.departure == null
                ? context.tr('Set departure')
                : context.tr('Departing from {p0}',
                    {'p0': widget.departure!.displayLabel}),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}

class _Selection {
  const _Selection(this.departure);
  final AssistantDeparture? departure;
}

class _DepartureDialog extends StatefulWidget {
  const _DepartureDialog({
    required this.departure,
    required this.service,
    required this.registerCancellation,
  });

  final AssistantDeparture? departure;
  final AssistantLocationService service;
  final ValueChanged<VoidCallback> registerCancellation;

  @override
  State<_DepartureDialog> createState() => _DepartureDialogState();
}

class _DepartureDialogState extends State<_DepartureDialog>
    with WidgetsBindingObserver {
  late final TextEditingController _city;
  AssistantDeparture? _selected;
  AssistantAirportSuggestion? _suggestion;
  AssistantLocationRequest? _request;
  String? _error;
  int _generation = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selected = widget.departure;
    _city = TextEditingController(text: widget.departure?.city ?? '');
    widget.registerCancellation(() {
      _cancel();
      _selected = null;
      _suggestion = null;
    });
  }

  void _cancel() {
    _generation++;
    _request?.cancel();
    _request = null;
    _busy = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Inactive may be the OS permission sheet. True backgrounding cancels.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      setState(_cancel);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    _city.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    _cancel();
    final generation = _generation;
    final request = _request = widget.service.start();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final suggestion = await request.result;
      if (!mounted || generation != _generation) return;
      setState(() {
        _selected = suggestion.departure;
        _suggestion = suggestion;
        _city.text = suggestion.departure.city;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = switch (error) {
            AssistantLocationFailure.denied =>
              'Location permission was not granted. Enter a departure city or airport.',
            AssistantLocationFailure.tooFar =>
              'No suitable airport was found within 250 km. Enter your preferred departure.',
            AssistantLocationFailure.timedOut =>
              'Location took too long. Enter a departure or try again.',
            _ =>
              'Could not find your location. Enter a departure city or airport.',
          });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _request = null;
        });
      }
    }
  }

  void _save() {
    final city = _city.text.trim();
    if (!isValidAssistantDepartureCity(city)) {
      setState(() =>
          _error = 'Enter a city or airport name (up to 100 characters).');
      return;
    }
    _cancel();
    Navigator.of(context).pop(_Selection(
        _selected?.city == city ? _selected : AssistantDeparture(city: city)));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('Your trip departure')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('assistant-departure-city'),
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 100,
                  inputFormatters: [
                    FilteringTextInputFormatter.singleLineFormatter
                  ],
                  decoration: InputDecoration(
                    labelText: context.tr('Departure city or airport'),
                    hintText: context.tr('City and country, or airport code'),
                  ),
                  onChanged: (_) => setState(() {
                    _cancel();
                    _selected = null;
                    _suggestion = null;
                    _error = null;
                  }),
                  onSubmitted: (_) => _save(),
                ),
                if (_selected?.airportCode != null) ...[
                  const SizedBox(height: 8),
                  Text(context.tr(
                      'Nearby airport: {p0}', {'p0': _selected!.displayLabel})),
                  if (_suggestion != null)
                    Text(context.tr(
                        'About {p0} km away. Change it if you prefer another departure.',
                        {'p0': _suggestion!.distanceKm.round().toString()})),
                ],
                const SizedBox(height: 12),
                Text(context.tr(
                    'Your device finds a nearby airport. Only the departure city and airport are shared with AI; coordinates stay on this device.')),
                const SizedBox(height: 8),
                if (_busy)
                  TextButton.icon(
                    onPressed: () => setState(_cancel),
                    icon: const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    label: Text(context.tr('Cancel location')),
                  )
                else
                  TextButton.icon(
                    key: const ValueKey('assistant-use-location'),
                    onPressed: _locate,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: Text(context.tr('Use my location')),
                  ),
                if (_error != null)
                  Text(context.tr(_error!),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
        ),
        actions: [
          if (widget.departure != null)
            TextButton(
              onPressed: () {
                _cancel();
                Navigator.of(context).pop(const _Selection(null));
              },
              child: Text(context.tr('Clear')),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(context.tr('Use departure')),
          ),
        ],
      );
}
