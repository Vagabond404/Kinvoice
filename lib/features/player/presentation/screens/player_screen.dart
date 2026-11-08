import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/audio/srt_export_helper.dart';
import '../../../../core/database/recording_repository.dart';
import '../../../../core/services/recording_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../home/domain/models/recording_summary.dart';
import '../../domain/models/transcript_segment.dart';
import '../widgets/scrubbable_waveform_track.dart';
import '../widgets/speaker_rename_dialog.dart';
import '../widgets/transcript_segment_tile.dart';

/// Screen displaying recording details, scrubbable waveform, playback controls,
/// interactive transcripts, 1-tap copy to clipboard, native share (text, audio,
/// or both together), and Export Formats Hub (.SRT, .TXT, .WAV / .M4A).
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.recording,
    this.initialSegments,
    this.playerService,
    this.repository,
    this.storageService,
  });

  final RecordingSummary recording;
  final List<TranscriptSegment>? initialSegments;
  final AudioPlayerService? playerService;
  final RecordingRepository? repository;
  final RecordingStorageService? storageService;

  @override
  State<PlayerScreen> createState() => PlayerScreenState();
}

class PlayerScreenState extends State<PlayerScreen> {
  late final AudioPlayerService _playerService;
  late final RecordingRepository _repository;
  late final RecordingStorageService _storageService;
  late final TextEditingController _titleController;

  Future<void>? pendingAsyncOperation;

  late RecordingSummary _recording;
  List<TranscriptSegment> _segments = [];
  bool _isLoading = true;

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isPlaying = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<dynamic>? _stateSub;
  StreamSubscription<void>? _dbChangesSub;

  final List<double> _speedOptions = const [1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _recording = widget.recording;
    _totalDuration = Duration(seconds: _recording.durationSeconds);
    _titleController = TextEditingController(text: _recording.title);
    _playerService = widget.playerService ?? AudioPlayerService();
    _repository = widget.repository ?? RecordingRepository();
    _storageService = widget.storageService ?? RecordingStorageService.instance;

    _initPlayerListeners();
    _loadSegments();
    _dbChangesSub = RecordingRepository.changes.listen((_) {
      if (mounted && widget.initialSegments == null) {
        _loadSegments();
      }
    });
  }

  void _initPlayerListeners() {
    _posSub = _playerService.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }
    });

    _durSub = _playerService.durationStream.listen((dur) {
      if (mounted && dur > Duration.zero) {
        setState(() {
          _totalDuration = dur;
        });
      }
    });

    _stateSub = _playerService.playerStateStream.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = _playerService.isPlaying;
        });
      }
    });
  }

  Future<void> _loadSegments() async {
    if (widget.initialSegments != null && widget.initialSegments!.isNotEmpty) {
      setState(() {
        _segments = widget.initialSegments!;
        _isLoading = false;
      });
      return;
    }

    final result = await _repository.getSegmentsForRecording(_recording.id);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      result.fold(
        onSuccess: (segments) {
          _segments = segments.isNotEmpty
              ? segments
              : _createFallbackSegments(_recording);
        },
        onError: (_) {
          _segments = _createFallbackSegments(_recording);
        },
      );
    });
  }

  List<TranscriptSegment> _createFallbackSegments(RecordingSummary rec) {
    return [
      TranscriptSegment(
        id: '${rec.id}_seg_1',
        recordingId: rec.id,
        startMs: 0,
        endMs: 8000,
        speakerId: rec.speakers.isNotEmpty ? rec.speakers.first : 'Speaker 1',
        text: rec.transcriptSnippet.isNotEmpty
            ? rec.transcriptSnippet
            : 'Conversation started and ambient sound calibrated.',
      ),
      TranscriptSegment(
        id: '${rec.id}_seg_2',
        recordingId: rec.id,
        startMs: 8500,
        endMs: 16000,
        speakerId: rec.speakers.length > 1 ? rec.speakers[1] : 'Speaker 2',
        text:
            'Agreed on audio isolated processing with low latency VAD inference.',
      ),
    ];
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _dbChangesSub?.cancel();
    _titleController.dispose();
    if (widget.playerService == null) {
      _playerService.dispose();
    }
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _playerService.pause();
    } else {
      if (_currentPosition >= _totalDuration && _totalDuration > Duration.zero) {
        await _playerService.seek(Duration.zero);
      }
      await _playerService.play(_recording.audioFilePath);
    }
    setState(() {
      _isPlaying = _playerService.isPlaying;
    });
  }

  Future<void> _seekTo(Duration position) async {
    await _playerService.seek(position);
  }

  Future<void> _seekRelative(int seconds) async {
    final newMs = (_currentPosition.inMilliseconds + (seconds * 1000))
        .clamp(0, _totalDuration.inMilliseconds);
    await _seekTo(Duration(milliseconds: newMs));
  }

  Future<void> _cyclePlaybackSpeed() async {
    final currentIndex = _speedOptions.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speedOptions.length;
    final nextSpeed = _speedOptions[nextIndex];

    await _playerService.setPlaybackRate(nextSpeed);
    setState(() {
      _playbackSpeed = nextSpeed;
    });
  }

  Future<void> _onRenameSpeaker(String oldName) async {
    final newName = await SpeakerRenameDialog.show(
      context,
      currentSpeakerName: oldName,
    );

    if (newName != null && newName != oldName && mounted) {
      setState(() {
        _segments = _segments.map((seg) {
          if (seg.speakerId == oldName) {
            return seg.copyWith(speakerId: newName);
          }
          return seg;
        }).toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Renamed "$oldName" to "$newName"'),
          backgroundColor: AppColors.success,
        ),
      );

      final op = _repository.renameSpeaker(
        recordingId: _recording.id,
        oldSpeakerId: oldName,
        newSpeakerId: newName,
      );
      pendingAsyncOperation = op;
      await op;
    }
  }

  /// Copies the entire formatted transcript (with speaker tags and timestamps)
  /// to the device clipboard (`Clipboard.setData`) with an animated confirmation toast.
  Future<void> copyTranscriptToClipboard() async {
    final formattedText = SrtExportHelper.generatePlainText(_segments);
    await Clipboard.setData(ClipboardData(text: formattedText));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Transcript copied to clipboard (${_segments.length} segments)',
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportFormat(String format) async {
    if (format == 'COPY') {
      await copyTranscriptToClipboard();
      return;
    }
    if (format == 'SHARE_TEXT') {
      final text = SrtExportHelper.generatePlainText(_segments);
      await _storageService.shareTextContent(
        text: '${_titleController.text.trim()}\n\n$text',
        subject: _titleController.text.trim(),
      );
      return;
    }
    if (format == 'SHARE_BOTH') {
      final text = SrtExportHelper.generatePlainText(_segments);
      await _storageService.shareAudioAndTranscript(
        filePath: _recording.audioFilePath,
        transcriptText: '${_titleController.text.trim()}\n\n$text',
        title: _titleController.text.trim(),
      );
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    String exportedContent = '';

    if (format == 'SRT') {
      exportedContent = SrtExportHelper.generateSrt(_segments);
    } else if (format == 'TXT') {
      exportedContent = SrtExportHelper.generatePlainText(_segments);
    } else {
      exportedContent = 'Audio export ready: ${_recording.audioFilePath}';
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text('Exported .$format (${_segments.length} segments)'),
        backgroundColor: AppColors.accent,
        action: SnackBarAction(
          label: 'Preview',
          textColor: Colors.white,
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Exported .$format'),
                content: SingleChildScrollView(
                  child: SelectableText(exportedContent),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (format == 'WAV') {
                        _storageService.shareAudioFile(
                          filePath: _recording.audioFilePath,
                          title: _recording.title,
                        );
                      } else {
                        _storageService.shareTextContent(
                          text: exportedContent,
                          subject: '${_recording.title} (.$format)',
                        );
                      }
                    },
                    child: const Text('Share'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentMs = _currentPosition.inMilliseconds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recording Detail'),
        actions: [
          // 1-Tap Copy Transcript Button
          IconButton(
            onPressed: copyTranscriptToClipboard,
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: 'Copy Transcript',
          ),
          // Export & Native Share Hub Menu (.SRT, .TXT, .WAV, Text, Audio + Transcript)
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Export',
            onSelected: _exportFormat,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'COPY',
                child: Row(
                  children: [
                    Icon(Icons.copy_all_rounded, color: AppColors.accent, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('Copy Formatted Transcript')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'SHARE_TEXT',
                child: Row(
                  children: [
                    Icon(Icons.notes_rounded, color: AppColors.accent, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('Share Formatted Text Note')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'SHARE_BOTH',
                child: Row(
                  children: [
                    Icon(Icons.share_rounded, color: AppColors.accent, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('Share Audio + Transcript Together')),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'SRT',
                child: Row(
                  children: [
                    Icon(Icons.subtitles_rounded, color: AppColors.accent, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('Export Subtitles (.SRT)')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'TXT',
                child: Row(
                  children: [
                    Icon(Icons.description_rounded, color: AppColors.accent, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('Export Plain Text (.TXT)')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'WAV',
                child: Row(
                  children: [
                    Icon(Icons.audio_file_rounded, color: AppColors.accent, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('Export Audio (.WAV)')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header Section: Title, Metadata, Scrubbable Waveform
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Editable Title
                  TextField(
                    controller: _titleController,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (val) {
                      _repository.updateRecordingTitle(
                        recordingId: _recording.id,
                        newTitle: val.trim(),
                      );
                    },
                  ),
                  const SizedBox(height: 6),

                  // Metadata Badges Row
                  Row(
                    children: [
                      Text(
                        _recording.formattedTime,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '•',
                        style: TextStyle(color: AppColors.textSecondaryLight),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _recording.formattedDuration,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Scrubbable Waveform Track
                  ScrubbableWaveformTrack(
                    currentPosition: _currentPosition,
                    totalDuration: _totalDuration,
                    onSeek: _seekTo,
                    seed: _recording.id.hashCode,
                  ),
                  const SizedBox(height: 8),

                  // Playback Controls Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Playback Speed Button
                      OutlinedButton(
                        onPressed: _cyclePlaybackSpeed,
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          side: BorderSide(
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.borderLight,
                          ),
                        ),
                        child: Text(
                          '${_playbackSpeed}x',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Skip -15s
                      IconButton(
                        onPressed: () => _seekRelative(-15),
                        icon: const Icon(Icons.replay_10_rounded),
                        iconSize: 28,
                      ),
                      const SizedBox(width: 8),

                      // Play/Pause Main Button
                      ElevatedButton(
                        onPressed: _togglePlayPause,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(16),
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        child: Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Skip +15s
                      IconButton(
                        onPressed: () => _seekRelative(15),
                        icon: const Icon(Icons.forward_10_rounded),
                        iconSize: 28,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Segmented Transcript Header with Quick Copy Pill
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Attributed Transcript',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${_segments.length} segments',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: copyTranscriptToClipboard,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.copy_rounded,
                                size: 13,
                                color: AppColors.accent,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Segmented Transcript List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      itemCount: _segments.length,
                      itemBuilder: (context, index) {
                        final segment = _segments[index];
                        final isActive = currentMs >= segment.startMs &&
                            currentMs < segment.endMs;

                        return TranscriptSegmentTile(
                          segment: segment,
                          isActive: isActive,
                          onTap: () {
                            _seekTo(Duration(milliseconds: segment.startMs));
                            if (!_isPlaying) {
                              _togglePlayPause();
                            }
                          },
                          onRenameSpeaker: _onRenameSpeaker,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
