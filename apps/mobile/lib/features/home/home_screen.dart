import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freedomtree_mobile/app/theme.dart';
import 'package:freedomtree_mobile/core/storage/app_database.dart';
import 'package:freedomtree_mobile/core/storage/surveys_dao.dart';
import 'package:freedomtree_mobile/core/storage/token_storage.dart';
import 'package:freedomtree_mobile/core/sync/sync_engine.dart';
import 'package:freedomtree_mobile/features/auth/auth_controller.dart';
import 'package:freedomtree_mobile/features/profile/profile_screen.dart';
import 'package:freedomtree_mobile/features/reports/report_enums.dart';
import 'package:freedomtree_mobile/features/reports/report_form_screen.dart';
import 'package:freedomtree_mobile/features/reports/reports_repository.dart';
import 'package:freedomtree_mobile/features/surveys/education_survey_form_screen.dart';
import 'package:freedomtree_mobile/features/surveys/maternal_survey_form_screen.dart';
import 'package:freedomtree_mobile/features/home/sync_sheet.dart';
import 'package:freedomtree_mobile/shared/ft_logo.dart';
import 'package:freedomtree_mobile/shared/skeleton.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.authController,
    required this.reportsRepository,
    required this.syncEngine,
    required this.surveysDao,
    required this.apiDio,
    required this.tokenStorage,
  });

  final AuthController authController;
  final ReportsRepository reportsRepository;
  final SyncEngine syncEngine;
  final SurveysDao surveysDao;
  final Dio apiDio;
  final TokenStorage tokenStorage;

  @override
  Widget build(BuildContext context) {
    final user = authController.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const FtLogo(height: 18),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen(authController: authController, apiDio: apiDio, tokenStorage: tokenStorage)),
            ),
          ),
          ListenableBuilder(
            listenable: syncEngine,
            builder: (ctx, _) {
              if (syncEngine.state == SyncState.syncing) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: FtColors.orange)),
                );
              }
              return Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    icon: const Icon(Icons.sync_rounded),
                    tooltip: 'Sync now',
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      final pendingReports = await reportsRepository.getPending();
                      final pendingEducation = await surveysDao.getPendingEducation();
                      final pendingMaternal = await surveysDao.getPendingMaternal();
                      if (!context.mounted) return;
                      if (pendingReports.isEmpty && pendingEducation.isEmpty && pendingMaternal.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Nothing to sync — all records are up to date.'), duration: Duration(seconds: 2)),
                        );
                        return;
                      }
                      await showSyncSheet(
                        context,
                        syncEngine: syncEngine,
                        pendingReports: pendingReports,
                        pendingEducation: pendingEducation,
                        pendingMaternal: pendingMaternal,
                      );
                    },
                  ),
                  if (syncEngine.pendingCount > 0)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: FtColors.orange, shape: BoxShape.circle),
                        child: Text('${syncEngine.pendingCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: authController.signOut,
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline banner
          ListenableBuilder(
            listenable: syncEngine,
            builder: (ctx, _) {
              if (syncEngine.state != SyncState.syncing && syncEngine.pendingCount > 0) {
                return Container(
                  width: double.infinity,
                  color: FtColors.yellow.withAlpha(230),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 16, color: FtColors.greyDarker),
                      const SizedBox(width: 8),
                      Text(
                        '${syncEngine.pendingCount} item${syncEngine.pendingCount == 1 ? "" : "s"} waiting to sync',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: FtColors.greyDarker),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                // Welcome card
                if (user != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [FtColors.greyDark, FtColors.greyDarker],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: FtColors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  user.name.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Welcome back', style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 12)),
                                  Text(user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (user.community != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 14, color: FtColors.greyLight),
                              const SizedBox(width: 4),
                              Text(user.community!, style: const TextStyle(color: FtColors.greyLight, fontSize: 12)),
                              const SizedBox(width: 16),
                              const Icon(Icons.work_outline_rounded, size: 14, color: FtColors.greyLight),
                              const SizedBox(width: 4),
                              Text(user.position, style: const TextStyle(color: FtColors.greyLight, fontSize: 12)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Action section
                const Text('Record data', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: FtColors.greyMedium, letterSpacing: 0.8)),
                const SizedBox(height: 10),

                _ActionCard(
                  icon: Icons.favorite_rounded,
                  iconColor: FtColors.orange,
                  title: 'Monthly health report',
                  subtitle: 'Maternal & infant mortality data',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ReportFormScreen(authController: authController, reportsRepository: reportsRepository)),
                  ).then((_) => syncEngine.syncPending()),
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.school_rounded,
                  iconColor: FtColors.green,
                  title: 'Education survey',
                  subtitle: 'School & community assessments',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EducationSurveyFormScreen(authController: authController, surveysDao: surveysDao)),
                  ).then((_) => syncEngine.syncPending()),
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.pregnant_woman_rounded,
                  iconColor: FtColors.yellow,
                  title: 'Maternal health survey',
                  subtitle: 'Pregnancy & birth outcome tracking',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MaternalSurveyFormScreen(authController: authController, surveysDao: surveysDao)),
                  ).then((_) => syncEngine.syncPending()),
                ),

                const SizedBox(height: 28),

                // Recent reports
                Row(
                  children: [
                    const Expanded(
                      child: Text('Recent reports', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: FtColors.greyMedium, letterSpacing: 0.8)),
                    ),
                    ListenableBuilder(
                      listenable: syncEngine,
                      builder: (ctx, _) => syncEngine.pendingCount > 0
                          ? Text('${syncEngine.pendingCount} pending', style: const TextStyle(fontSize: 12, color: FtColors.orange, fontWeight: FontWeight.w600))
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                StreamBuilder<List<LocalReport>>(
                  stream: reportsRepository.watchAll(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: const Column(
                          children: [
                            ReportTileSkeleton(),
                            Divider(height: 1, indent: 16, endIndent: 16),
                            ReportTileSkeleton(),
                            Divider(height: 1, indent: 16, endIndent: 16),
                            ReportTileSkeleton(),
                          ],
                        ),
                      );
                    }
                    final reports = snapshot.data ?? [];
                    if (reports.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: const Column(
                          children: [
                            Icon(Icons.description_outlined, size: 40, color: FtColors.greyLight),
                            SizedBox(height: 12),
                            Text('No reports yet', style: TextStyle(fontWeight: FontWeight.w600, color: FtColors.greyDark)),
                            SizedBox(height: 4),
                            Text('Tap "Monthly health report" to get started', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: FtColors.greyMedium)),
                          ],
                        ),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          for (int i = 0; i < reports.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                            _ReportTile(report: reports[i]),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.iconColor, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: FtColors.greyDarker)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: FtColors.greyMedium)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: FtColors.greyLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});
  final LocalReport report;

  @override
  Widget build(BuildContext context) {
    final month = reportingMonths[report.reportingMonth.month - 1];
    final year = report.reportingMonth.year;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text('$month $year — ${report.community}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('${report.maternalDeaths} maternal · ${report.infantDeathsTotal} infant deaths', style: const TextStyle(fontSize: 12, color: FtColors.greyMedium)),
      ),
      trailing: _SyncBadge(status: report.syncStatus),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.status});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SyncStatus.synced   => ('Synced', FtColors.green),
      SyncStatus.pending  => ('Pending', FtColors.yellow),
      SyncStatus.syncing  => ('Syncing…', FtColors.orange),
      SyncStatus.failed   => ('Failed', FtColors.darkOrange),
      SyncStatus.draft    => ('Draft', FtColors.greyLight),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
