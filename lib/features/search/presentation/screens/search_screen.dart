import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../../core/ai/vector_search/hybrid_search_engine.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/theme/app_colors.dart';

/// The "Ask Memory" screen of Kinvoice.
/// Provides conversational natural language queries, hybrid vector & FTS5 search,
/// generative answer cards with clickable citation chips, and embedded preview players.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.searchEngine,
    this.playerService,
  });

  final HybridSearchEngine? searchEngine;
  final AudioPlayerService? playerService;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final HybridSearchEngine _searchEngine;
  AudioPlayerService? _playerService;

  final TextEditingController _searchController = TextEditingController();
  int _selectedFilterIndex = 0;
  bool _isSearching = false;
  HybridSearchResponse? _searchResponse;

  String? _currentlyPlayingSegmentId;
  bool _isPlaying = false;
  StreamSubscription<PlayerState>? _playerStateSub;

  final List<String> _filters = const [
    'All Notes',
    'Decisions',
    'Meetings',
    'Ideas',
    'Today',
  ];

  final List<String> _suggestedQueries = const [
    "What did I decide in yesterday's meeting about marketing?",
    'What tasks were agreed on during the sprint sync?',
    'What did Mom say about the weekend dinner?',
  ];

  @override
  void initState() {
    super.initState();
    _searchEngine = widget.searchEngine ?? HybridSearchEngine();
    _playerService = widget.playerService;
  }

  AudioPlayerService get playerService =>
      _playerService ??= AudioPlayerService();

  @override
  void dispose() {
    _searchController.dispose();
    _playerStateSub?.cancel();
    if (widget.playerService == null) {
      _playerService?.dispose();
    }
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() {
        _searchResponse = null;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final response = await _searchEngine.search(query: clean);
      if (!mounted) return;
      setState(() {
        _searchResponse = response;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  Future<void> _toggleAudioPreview(HybridSearchResult result) async {
    final svc = playerService;
    if (_currentlyPlayingSegmentId == result.segmentId && _isPlaying) {
      await svc.pause();
      setState(() => _isPlaying = false);
    } else {
      if (result.audioFilePath.isNotEmpty) {
        await svc.play(
          result.audioFilePath,
          initialPosition: Duration(milliseconds: result.startMs),
        );
      }
      setState(() {
        _currentlyPlayingSegmentId = result.segmentId;
        _isPlaying = true;
      });

      _playerStateSub?.cancel();
      _playerStateSub = svc.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });
    }
  }

  void _onCitationTapped(CitationChip citation) {
    if (_searchResponse == null) return;
    final match = _searchResponse!.results.firstWhere(
      (r) =>
          r.recordingId == citation.recordingId &&
          r.startMs == citation.startMs,
      orElse: () => _searchResponse!.results.first,
    );
    _toggleAudioPreview(match);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.accent,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Ask Your Memory',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Search across all your spoken conversations with on-device AI.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar Input
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceContainerDark
                        : AppColors.surfaceContainerLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _performSearch,
                    decoration: InputDecoration(
                      hintText: 'e.g. What did I decide in yesterday\'s meeting about marketing?',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.accent,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _performSearch('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (text) {
                      if (text.isEmpty) {
                        _performSearch('');
                      }
                    },
                  ),
                ),
              ),
            ),

            // Filter Chips Row
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  itemCount: _filters.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedFilterIndex;
                    return FilterChip(
                      selected: isSelected,
                      label: Text(_filters[index]),
                      labelStyle: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      backgroundColor: isDark
                          ? AppColors.surfaceContainerDark
                          : AppColors.surfaceContainerLight,
                      selectedColor: AppColors.accent,
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.accent
                              : (isDark
                                  ? AppColors.borderDark
                                  : AppColors.borderLight),
                        ),
                      ),
                      onSelected: (_) {
                        setState(() => _selectedFilterIndex = index);
                      },
                    );
                  },
                ),
              ),
            ),

            if (_isSearching)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                ),
              ),

            // Generative Answer Summary Card
            if (_searchResponse != null && _searchResponse!.results.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(
                        color: AppColors.accent,
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.psychology_rounded,
                                  color: AppColors.accent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'AI Answer Summary',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'all-MiniLM-L6-v2',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _searchResponse!.generativeSummary,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                          if (_searchResponse!.citations.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 6),
                            Text(
                              'Citations (Tap to listen):',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: _searchResponse!.citations.map((cit) {
                                return ActionChip(
                                  avatar: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    size: 16,
                                    color: AppColors.accent,
                                  ),
                                  label: Text(
                                    '${cit.speakerId} [${cit.formattedTimeRange}]',
                                  ),
                                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  onPressed: () => _onCitationTapped(cit),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Search Results List
            if (_searchResponse != null && _searchResponse!.results.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Relevant Spoken Moments (${_searchResponse!.results.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _searchResponse!.results[index];
                    final isThisPlaying =
                        _currentlyPlayingSegmentId == item.segmentId && _isPlaying;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Card Header: Recording title & match badge
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.recordingTitle,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${(item.combinedScore * 100).toInt()}% Match',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.surfaceContainerDark
                                          : AppColors.surfaceContainerLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.speakerId,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    item.formattedTimeRange,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item.text,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Embedded Audio Preview Player
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.surfaceContainerDark
                                      : AppColors.surfaceContainerLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        isThisPlaying
                                            ? Icons.pause_circle_filled_rounded
                                            : Icons.play_circle_fill_rounded,
                                        color: AppColors.accent,
                                        size: 32,
                                      ),
                                      onPressed: () => _toggleAudioPreview(item),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isThisPlaying ? 'Playing Audio Preview' : 'Play Audio Clip',
                                            style: theme.textTheme.labelMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${item.formattedStartTime} - ${item.formattedEndTime}',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              color: isDark
                                                  ? AppColors.textSecondaryDark
                                                  : AppColors.textSecondaryLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _searchResponse!.results.length,
                ),
              ),
            ],

            // Suggested Queries Section (Shown when query is empty)
            if (_searchResponse == null || _searchResponse!.results.isEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                    'Suggested Questions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              ..._suggestedQueries.map((suggested) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: AppColors.accent,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          suggested,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                        ),
                        onTap: () {
                          _searchController.text = suggested;
                          _performSearch(suggested);
                        },
                      ),
                    ),
                  ),
                );
              }),
            ],

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }
}
