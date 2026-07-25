import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:freedomtree_mobile/core/storage/app_database.dart';
import 'package:freedomtree_mobile/core/storage/reports_dao.dart';
import 'package:freedomtree_mobile/core/storage/surveys_dao.dart';
import 'package:freedomtree_mobile/features/reports/reports_repository.dart';
import 'package:freedomtree_mobile/features/surveys/surveys_repository.dart';

enum SyncState { idle, syncing, error }

/// Orchestrates offline→online sync. Call [syncPending()] from three paths:
///   1. Connectivity-restored event (wired up in [startListening]).
///   2. App resume (caller's responsibility to invoke this method).
///   3. Manual "Sync now" / pull-to-refresh from the home screen.
///
/// Processes PENDING/FAILED rows sequentially (gentle on weak connections).
/// A 409 (server already has this community+month from a different clientId)
/// sets the row to FAILED with a human-readable error so the UI can surface
/// it — the field worker can then contact an admin to reconcile.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required ReportsDao dao,
    required ReportsRepository repository,
    required SurveysDao surveysDao,
    required SurveysRepository surveysRepository,
  })  : _dao = dao,
        _repository = repository,
        _surveysDao = surveysDao,
        _surveysRepository = surveysRepository;

  final ReportsDao _dao;
  final ReportsRepository _repository;
  final SurveysDao _surveysDao;
  final SurveysRepository _surveysRepository;

  SyncState state = SyncState.idle;
  int pendingCount = 0;
  int syncedThisSession = 0;   // how many completed in current syncPending call
  int totalThisSession = 0;    // total queued in current syncPending call
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  void startListening() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) syncPending();
    });
  }

  /// Sync all pending records. Pass [selectedReportIds] / [selectedEducationIds] /
  /// [selectedMaternalIds] to restrict which records are uploaded.
  /// Passing null means "sync all of that type".
  Future<void> syncPending({
    Set<String>? selectedReportIds,
    Set<String>? selectedEducationIds,
    Set<String>? selectedMaternalIds,
  }) async {
    if (state == SyncState.syncing) return;

    final allReports = await _dao.getPending();
    final allEducation = await _surveysDao.getPendingEducation();
    final allMaternal = await _surveysDao.getPendingMaternal();

    final rows = selectedReportIds == null
        ? allReports
        : allReports.where((r) => selectedReportIds.contains(r.clientId)).toList();
    final educationRows = selectedEducationIds == null
        ? allEducation
        : allEducation.where((r) => selectedEducationIds.contains(r.clientId)).toList();
    final maternalRows = selectedMaternalIds == null
        ? allMaternal
        : allMaternal.where((r) => selectedMaternalIds.contains(r.clientId)).toList();

    if (rows.isEmpty && educationRows.isEmpty && maternalRows.isEmpty) {
      _updatePendingCount();
      return;
    }

    syncedThisSession = 0;
    totalThisSession = rows.length + educationRows.length + maternalRows.length;
    state = SyncState.syncing;
    notifyListeners();

    for (final row in rows) {
      await _syncRow(row);
      syncedThisSession++;
      notifyListeners();
    }

    for (final row in educationRows) {
      await _syncEducationRow(row);
      syncedThisSession++;
      notifyListeners();
    }

    for (final row in maternalRows) {
      await _syncMaternalRow(row);
      syncedThisSession++;
      notifyListeners();
    }

    await _updatePendingCount();
    state = SyncState.idle;
    notifyListeners();
  }

  Future<void> _syncRow(LocalReport row) async {
    await _dao.markSyncing(row.clientId);

    // Reconstruct the JSON payload from the stored row.
    final draft = _dao.toDraft(row);
    final payload = draft.toJson(row.clientUpdatedAt);

    try {
      final serverId = await _repository.submitForSync(payload);
      await _dao.markSynced(row.clientId, serverId);
    } on ReportConflictException {
      await _dao.markFailed(
        row.clientId,
        'This community already has a report for this month. Contact your administrator.',
      );
    } on ReportSubmitException catch (e) {
      await _dao.markFailed(row.clientId, e.message);
    } catch (e) {
      await _dao.markFailed(row.clientId, e.toString());
    }
  }

  Future<void> _syncEducationRow(LocalEducationSurvey row) async {
    await _surveysDao.markEducationSyncing(row.clientId);
    try {
      final answers = jsonDecode(row.answersJson) as Map<String, dynamic>;
      final payload = {
        'clientId': row.clientId,
        'enumeratorName': row.enumeratorName,
        'surveyDate': row.surveyDate.toUtc().toIso8601String(),
        'communityOrSchool': row.communityOrSchool,
        'district': row.district,
        'respondentName': row.respondentName,
        'respondentCategory': row.respondentCategory,
        'sex': row.sex,
        'answers': answers,
        'clientCreatedAt': row.clientCreatedAt.toUtc().toIso8601String(),
        'clientUpdatedAt': row.clientUpdatedAt.toUtc().toIso8601String(),
      };
      final serverId = await _surveysRepository.submitEducationForSync(payload);
      await _surveysDao.markEducationSynced(row.clientId, serverId);
    } on SurveySubmitException catch (e) {
      await _surveysDao.markEducationFailed(row.clientId, e.message);
    } catch (e) {
      await _surveysDao.markEducationFailed(row.clientId, e.toString());
    }
  }

  Future<void> _syncMaternalRow(LocalMaternalSurvey row) async {
    await _surveysDao.markMaternalSyncing(row.clientId);
    try {
      final answers = jsonDecode(row.answersJson) as Map<String, dynamic>;
      final payload = <String, dynamic>{
        'clientId': row.clientId,
        'enumeratorName': row.enumeratorName,
        'surveyDate': row.surveyDate.toUtc().toIso8601String(),
        'community': row.community,
        'district': row.district,
        'respondentName': row.respondentName,
        'respondentCategory': row.respondentCategory,
        'sex': row.sex,
        'answers': answers,
        'clientCreatedAt': row.clientCreatedAt.toUtc().toIso8601String(),
        'clientUpdatedAt': row.clientUpdatedAt.toUtc().toIso8601String(),
      };
      if (row.healthFacility != null) payload['healthFacility'] = row.healthFacility;
      final serverId = await _surveysRepository.submitMaternalForSync(payload);
      await _surveysDao.markMaternalSynced(row.clientId, serverId);
    } on SurveySubmitException catch (e) {
      await _surveysDao.markMaternalFailed(row.clientId, e.message);
    } catch (e) {
      await _surveysDao.markMaternalFailed(row.clientId, e.toString());
    }
  }

  Future<void> _updatePendingCount() async {
    final pending = await _dao.getPending();
    final pendingEdu = await _surveysDao.getPendingEducation();
    final pendingMat = await _surveysDao.getPendingMaternal();
    pendingCount = pending.length + pendingEdu.length + pendingMat.length;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
