import 'package:flutter/material.dart';
import '../../../../core/services/recording_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../recording/presentation/screens/recording_screen.dart';
import '../../domain/models/recording_summary.dart';
import '../view_models/home_view_model.dart';
import '../widgets/hero_quick_record_card.dart';
import '../widgets/recording_feed_item.dart';
import '../widgets/time_filter_selector.dart';

/// The Timeline / Home Screen for Kinvoice.
/// Features a CustomScrollView with slivers, Hero Record Card, Time Filters,
/// real SQLite recordings feed, and interactive playback/management.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.viewModel,
  });

  final HomeViewModel? viewModel;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? HomeViewModel();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) {
      _viewModel.dispose();
    }
    super.dispose();
  }

  Future<void> _openRecordingModal(BuildContext context) async {
    await _viewModel.stopPlayback();
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final savedPath = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const RecordingScreen(),
      ),
    );

    if (!mounted) return;

    if (savedPath != null) {
      await _viewModel.loadRecordings();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Recording saved & transcribing: $savedPath'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _openPlayerScreen(RecordingSummary recording) async {
    await _viewModel.stopPlayback();
    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(recording: recording),
      ),
    );

    if (!mounted) return;
    await _viewModel.loadRecordings();
  }

  Future<void> _showRecordingActionsSheet(RecordingSummary recording) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  recording.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: AppColors.accent),
                title: const Text('Rename Recording'),
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.ios_share_rounded, color: AppColors.accent),
                title: const Text('Share Audio File'),
                onTap: () => Navigator.pop(ctx, 'share'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.recording,
                ),
                title: const Text(
                  'Delete Recording',
                  style: TextStyle(color: AppColors.recording),
                ),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || selectedAction == null) return;

    if (selectedAction == 'rename') {
      await _promptRenameDialog(recording);
    } else if (selectedAction == 'share') {
      await RecordingStorageService.instance.shareAudioFile(
        filePath: recording.audioFilePath,
        title: recording.title,
      );
    } else if (selectedAction == 'delete') {
      await _confirmDeleteDialog(recording);
    }
  }

  Future<void> _promptRenameDialog(RecordingSummary recording) async {
    final controller = TextEditingController(text: recording.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Recording'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Recording Title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newTitle != null && newTitle.isNotEmpty && mounted) {
      await _viewModel.renameRecording(recording.id, newTitle);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Renamed to "$newTitle"'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _confirmDeleteDialog(RecordingSummary recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: Text(
          'Are you sure you want to permanently delete "${recording.title}" and its local audio file?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.recording,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _viewModel.deleteRecording(recording.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording and local audio file deleted.'),
          backgroundColor: AppColors.recording,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            final allRecordings = _viewModel.allRecordings;
            final recordings = _viewModel.filteredRecordings;

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Top App Bar with Ambient Status Indicator
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kinvoice',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Ambient Memory: Active',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton.filledTonal(
                          onPressed: _viewModel.loadRecordings,
                          tooltip: 'Refresh Recordings',
                          icon: const Icon(Icons.refresh_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? AppColors.surfaceContainerDark
                                : AppColors.surfaceContainerLight,
                            foregroundColor: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Hero Quick Record Card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: HeroQuickRecordCard(
                      isRecording: _viewModel.isRecording,
                      onRecordTap: () => _openRecordingModal(context),
                    ),
                  ),
                ),

                // Time / Category Filter Selector
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: TimeFilterSelector(
                      filters: _viewModel.availableFilters,
                      selectedFilter: _viewModel.selectedFilter,
                      onFilterSelected: _viewModel.selectFilter,
                    ),
                  ),
                ),

                // Feed Section Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Conversations',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceContainerDark
                                : AppColors.surfaceContainerLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${recordings.length} ${recordings.length == 1 ? 'item' : 'items'}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Recording Feed Items or Stitch-Style Empty State
                if (allRecordings.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 48,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceContainerDark
                              : AppColors.surfaceContainerLight,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.borderLight,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.graphic_eq_rounded,
                                size: 36,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'No voice notes yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the record button above to capture your first thought.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (recordings.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.filter_list_off_rounded,
                            size: 48,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No recordings found for "${_viewModel.selectedFilter}"',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    sliver: SliverList.separated(
                      itemCount: recordings.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final recording = recordings[index];
                        final isPlaying = _viewModel.isPlaying &&
                            _viewModel.activePlayingId == recording.id;

                        return RecordingFeedItem(
                          recording: recording,
                          isPlaying: isPlaying,
                          onFavoriteToggle: () =>
                              _viewModel.toggleFavorite(recording.id),
                          onPlayToggle: () =>
                              _viewModel.togglePlay(recording.id),
                          onTap: () => _openPlayerScreen(recording),
                          onLongPress: () =>
                              _showRecordingActionsSheet(recording),
                        );
                      },
                    ),
                  ),

                // Bottom safe inset spacer for navigation dock
                const SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
