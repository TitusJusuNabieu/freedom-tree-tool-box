import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freedomtree_mobile/app/theme.dart';
import 'package:freedomtree_mobile/core/storage/app_database.dart';
import 'package:freedomtree_mobile/core/sync/sync_engine.dart';
import 'package:freedomtree_mobile/features/reports/report_enums.dart';

/// Bottom sheet for selective sync with real-time progress.
/// Call via [showSyncSheet].
Future<void> showSyncSheet(
  BuildContext context, {
  required SyncEngine syncEngine,
  required List<LocalReport> pendingReports,
  required List<LocalEducationSurvey> pendingEducation,
  required List<LocalMaternalSurvey> pendingMaternal,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SyncSheet(
      syncEngine: syncEngine,
      pendingReports: pendingReports,
      pendingEducation: pendingEducation,
      pendingMaternal: pendingMaternal,
    ),
  );
}

class _SyncSheet extends StatefulWidget {
  const _SyncSheet({
    required this.syncEngine,
    required this.pendingReports,
    required this.pendingEducation,
    required this.pendingMaternal,
  });

  final SyncEngine syncEngine;
  final List<LocalReport> pendingReports;
  final List<LocalEducationSurvey> pendingEducation;
  final List<LocalMaternalSurvey> pendingMaternal;

  @override
  State<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<_SyncSheet> {
  late final Set<String> _selectedReports;
  late final Set<String> _selectedEducation;
  late final Set<String> _selectedMaternal;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _selectedReports = {for (final r in widget.pendingReports) r.clientId};
    _selectedEducation = {for (final r in widget.pendingEducation) r.clientId};
    _selectedMaternal = {for (final r in widget.pendingMaternal) r.clientId};
  }

  int get _totalSelected =>
      _selectedReports.length + _selectedEducation.length + _selectedMaternal.length;

  Future<void> _startSync() async {
    if (_totalSelected == 0) return;
    HapticFeedback.mediumImpact();

    await widget.syncEngine.syncPending(
      selectedReportIds: _selectedReports,
      selectedEducationIds: _selectedEducation,
      selectedMaternalIds: _selectedMaternal,
    );

    if (mounted) {
      setState(() => _done = true);
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: ListenableBuilder(
        listenable: widget.syncEngine,
        builder: (ctx, _) {
          final engine = widget.syncEngine;
          final isSyncing = engine.state == SyncState.syncing;
          final progress = engine.totalThisSession > 0
              ? engine.syncedThisSession / engine.totalThisSession
              : 0.0;

          if (_done) {
            return _DoneState(syncedCount: engine.syncedThisSession);
          }

          if (isSyncing) {
            return _ProgressState(progress: progress, engine: engine);
          }

          return _SelectionState(
            pendingReports: widget.pendingReports,
            pendingEducation: widget.pendingEducation,
            pendingMaternal: widget.pendingMaternal,
            selectedReports: _selectedReports,
            selectedEducation: _selectedEducation,
            selectedMaternal: _selectedMaternal,
            totalSelected: _totalSelected,
            onToggleReport: (id, v) => setState(() => v ? _selectedReports.add(id) : _selectedReports.remove(id)),
            onToggleEducation: (id, v) => setState(() => v ? _selectedEducation.add(id) : _selectedEducation.remove(id)),
            onToggleMaternal: (id, v) => setState(() => v ? _selectedMaternal.add(id) : _selectedMaternal.remove(id)),
            onSelectAll: () => setState(() {
              _selectedReports.addAll(widget.pendingReports.map((r) => r.clientId));
              _selectedEducation.addAll(widget.pendingEducation.map((r) => r.clientId));
              _selectedMaternal.addAll(widget.pendingMaternal.map((r) => r.clientId));
            }),
            onDeselectAll: () => setState(() {
              _selectedReports.clear();
              _selectedEducation.clear();
              _selectedMaternal.clear();
            }),
            onSync: _startSync,
          );
        },
      ),
    );
  }
}

// ── Selection state ───────────────────────────────────────────────────────────

class _SelectionState extends StatelessWidget {
  const _SelectionState({
    required this.pendingReports,
    required this.pendingEducation,
    required this.pendingMaternal,
    required this.selectedReports,
    required this.selectedEducation,
    required this.selectedMaternal,
    required this.totalSelected,
    required this.onToggleReport,
    required this.onToggleEducation,
    required this.onToggleMaternal,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onSync,
  });

  final List<LocalReport> pendingReports;
  final List<LocalEducationSurvey> pendingEducation;
  final List<LocalMaternalSurvey> pendingMaternal;
  final Set<String> selectedReports;
  final Set<String> selectedEducation;
  final Set<String> selectedMaternal;
  final int totalSelected;
  final void Function(String, bool) onToggleReport;
  final void Function(String, bool) onToggleEducation;
  final void Function(String, bool) onToggleMaternal;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final total = pendingReports.length + pendingEducation.length + pendingMaternal.length;
    final allSelected = totalSelected == total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Expanded(
              child: Text('Sync records', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: FtColors.greyDarker)),
            ),
            TextButton(
              onPressed: allSelected ? onDeselectAll : onSelectAll,
              child: Text(allSelected ? 'Deselect all' : 'Select all', style: const TextStyle(color: FtColors.orange, fontSize: 13)),
            ),
          ],
        ),
        Text('$totalSelected of $total selected', style: const TextStyle(color: FtColors.greyMedium, fontSize: 13)),
        const SizedBox(height: 12),

        // Records list
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (pendingReports.isNotEmpty) ...[
                _GroupHeader('Health Reports', pendingReports.length),
                ...pendingReports.map((r) {
                  final month = reportingMonths[r.reportingMonth.month - 1];
                  final year = r.reportingMonth.year;
                  return _RecordTile(
                    icon: Icons.favorite_rounded,
                    iconColor: FtColors.orange,
                    title: '$month $year',
                    subtitle: r.community,
                    checked: selectedReports.contains(r.clientId),
                    onChanged: (v) => onToggleReport(r.clientId, v ?? false),
                  );
                }),
              ],
              if (pendingEducation.isNotEmpty) ...[
                _GroupHeader('Education Surveys', pendingEducation.length),
                ...pendingEducation.map((r) => _RecordTile(
                  icon: Icons.school_rounded,
                  iconColor: FtColors.green,
                  title: r.communityOrSchool,
                  subtitle: r.surveyDate.toLocal().toString().substring(0, 10),
                  checked: selectedEducation.contains(r.clientId),
                  onChanged: (v) => onToggleEducation(r.clientId, v ?? false),
                )),
              ],
              if (pendingMaternal.isNotEmpty) ...[
                _GroupHeader('Maternal Surveys', pendingMaternal.length),
                ...pendingMaternal.map((r) => _RecordTile(
                  icon: Icons.pregnant_woman_rounded,
                  iconColor: FtColors.yellow,
                  title: r.community,
                  subtitle: r.surveyDate.toLocal().toString().substring(0, 10),
                  checked: selectedMaternal.contains(r.clientId),
                  onChanged: (v) => onToggleMaternal(r.clientId, v ?? false),
                )),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: totalSelected == 0 ? null : onSync,
            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
            label: Text('Sync $totalSelected record${totalSelected == 1 ? "" : "s"}'),
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label, this.count);
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        '$label ($count)',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: FtColors.greyMedium, letterSpacing: 0.5),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool checked;
  final void Function(bool?) onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: checked,
      onChanged: onChanged,
      activeColor: FtColors.orange,
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: FtColors.greyMedium)),
    );
  }
}

// ── Progress state ────────────────────────────────────────────────────────────

class _ProgressState extends StatelessWidget {
  const _ProgressState({required this.progress, required this.engine});
  final double progress;
  final SyncEngine engine;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        const Text('Syncing…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: FtColors.greyDarker)),
        const SizedBox(height: 20),
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          tween: Tween(begin: 0, end: progress),
          builder: (_, value, __) => Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: FtColors.greyLight.withAlpha(60),
                  color: FtColors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${engine.syncedThisSession} of ${engine.totalThisSession} uploaded',
                style: const TextStyle(fontSize: 13, color: FtColors.greyMedium),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── Done state ────────────────────────────────────────────────────────────────

class _DoneState extends StatelessWidget {
  const _DoneState({required this.syncedCount});
  final int syncedCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.cloud_done_rounded, color: FtColors.green, size: 52),
        const SizedBox(height: 12),
        Text(
          '$syncedCount record${syncedCount == 1 ? "" : "s"} synced!',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: FtColors.greyDarker),
        ),
        const SizedBox(height: 6),
        const Text('Closing…', style: TextStyle(fontSize: 13, color: FtColors.greyMedium)),
        const SizedBox(height: 20),
      ],
    );
  }
}
