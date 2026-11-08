import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../recording/presentation/screens/recording_screen.dart';
import '../view_models/home_view_model.dart';
import '../widgets/hero_quick_record_card.dart';
import '../widgets/recording_feed_item.dart';
import '../widgets/time_filter_selector.dart';

/// The Timeline / Home Screen for Kinvoice.
/// Features a CustomScrollView with slivers, Hero Record Card, Time Filters, and chronologically grouped recordings.
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
      messenger.showSnackBar(
        SnackBar(
          content: Text('Recording saved: $savedPath'),
          backgroundColor: AppColors.success,
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
                          onPressed: () {},
                          icon: const Icon(Icons.notifications_none_rounded),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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

                // Recording Feed Items or Empty State
                if (recordings.isEmpty)
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    sliver: SliverList.separated(
                      itemCount: recordings.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final recording = recordings[index];
                        final isPlaying =
                            _viewModel.isPlaying &&
                            _viewModel.activePlayingId == recording.id;

                        return RecordingFeedItem(
                          recording: recording,
                          isPlaying: isPlaying,
                          onFavoriteToggle: () => _viewModel.toggleFavorite(recording.id),
                          onPlayToggle: () => _viewModel.togglePlay(recording.id),
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
