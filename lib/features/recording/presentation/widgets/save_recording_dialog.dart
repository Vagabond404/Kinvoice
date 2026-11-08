import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/database/recording_repository.dart';
import '../../../../core/ml/asr/asr_engine.dart';
import '../../../../core/ml/transcription_worker.dart';
import '../../../../core/services/app_preferences_service.dart';
import '../../../../core/services/recording_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../home/domain/models/recording_summary.dart';
import '../../../player/domain/models/transcript_segment.dart';

/// Outcome returned when the user completes or dismisses the [SaveRecordingDialog].
enum SaveRecordingAction {
  saved,
  discarded,
}

/// Result returned by [SaveRecordingDialog.show].
@immutable
class SaveRecordingDialogResult {
  const SaveRecordingDialogResult({
    required this.action,
    this.recording,
    this.savedFilePath,
  });

  final SaveRecordingAction action;
  final RecordingSummary? recording;
  final String? savedFilePath;

  bool get isSaved => action == SaveRecordingAction.saved;
}

/// Interactive Save & Tag modal displayed immediately after finishing a recording.
class SaveRecordingDialog extends StatefulWidget {
  const SaveRecordingDialog({
    super.key,
    required this.tempFilePath,
    required this.duration,
    required this.fileSizeBytes,
    required this.targetDirectoryPath,
    this.initialTitle,
    this.initialCategory = 'General',
    this.storageService,
    this.repository,
    this.preferencesService,
    this.transcriptionCoordinator,
  });

  final String tempFilePath;
  final Duration duration;
  final int fileSizeBytes;
  final String targetDirectoryPath;
  final String? initialTitle;
  final String initialCategory;
  final RecordingStorageService? storageService;
  final RecordingRepository? repository;
  final AppPreferencesService? preferencesService;
  final TranscriptionWorkerCoordinator? transcriptionCoordinator;

  static const List<String> categories = [
    'General',
    'Meetings',
    'Ideas',
    'Personal',
    'Projects',
  ];

  /// Formats a [DateTime] into `"Voice Note YYYY-MM-DD HH:mm"`.
  static String defaultVoiceNoteTitle([DateTime? dateTime]) {
    final now = dateTime ?? DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'Voice Note $y-$m-$d $hh:$mm';
  }

  /// Displays the Save & Tag modal bottom sheet and returns the user's decision.
  static Future<SaveRecordingDialogResult?> show(
    BuildContext context, {
    required String tempFilePath,
    required Duration duration,
    String? initialTitle,
    String initialCategory = 'General',
    RecordingStorageService? storageService,
    RecordingRepository? repository,
    AppPreferencesService? preferencesService,
    TranscriptionWorkerCoordinator? transcriptionCoordinator,
  }) async {
    final storage = storageService ?? RecordingStorageService.instance;
    final fileSizeBytes = await storage.getFileSizeBytes(tempFilePath);
    final targetDir = await storage.getRecordingsDirectoryPath();

    if (!context.mounted) return null;

    return showModalBottomSheet<SaveRecordingDialogResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SaveRecordingDialog(
        tempFilePath: tempFilePath,
        duration: duration,
        fileSizeBytes: fileSizeBytes,
        targetDirectoryPath: targetDir,
        initialTitle: initialTitle,
        initialCategory: initialCategory,
        storageService: storage,
        repository: repository,
        preferencesService: preferencesService,
        transcriptionCoordinator: transcriptionCoordinator,
      ),
    );
  }

  @override
  State<SaveRecordingDialog> createState() => _SaveRecordingDialogState();
}

class _SaveRecordingDialogState extends State<SaveRecordingDialog> {
  late final TextEditingController _titleController;
  late final RecordingStorageService _storageService;
  late final RecordingRepository _repository;
  late final AppPreferencesService _preferencesService;

  late String _selectedCategory;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageService ?? RecordingStorageService.instance;
    _repository = widget.repository ?? RecordingRepository();
    _preferencesService =
        widget.preferencesService ?? AppPreferencesService.instance;

    final defaultTitle = SaveRecordingDialog.defaultVoiceNoteTitle();
    final initial = widget.initialTitle?.trim() ?? '';
    final resolvedTitle =
        (initial.isEmpty || initial == 'New Recording') ? defaultTitle : initial;

    _titleController = TextEditingController(text: resolvedTitle);
    _selectedCategory =
        SaveRecordingDialog.categories.contains(widget.initialCategory)
            ? widget.initialCategory
            : SaveRecordingDialog.categories.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String _formatDurationMmSs(Duration d) {
    final totalSeconds = d.inSeconds > 0 ? d.inSeconds : 1;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _handleDiscard() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    await _storageService.deleteAudioFile(widget.tempFilePath);

    if (!mounted) return;
    Navigator.of(context).pop(
      const SaveRecordingDialogResult(
        action: SaveRecordingAction.discarded,
      ),
    );
  }

  Future<void> _handleSaveAndTranscribe() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    final now = DateTime.now();
    final rawTitle = _titleController.text.trim();
    final finalTitle = rawTitle.isNotEmpty
        ? rawTitle
        : SaveRecordingDialog.defaultVoiceNoteTitle(now);

    final formatExt = _preferencesService.audioFormat.extension;

    // 1. Move temporary audio file into persistent Kinvoice/Recordings directory
    final savedFilePath = await _storageService.persistRecordingFile(
      tempFilePath: widget.tempFilePath,
      category: _selectedCategory,
      timestamp: now,
      formatExtension: formatExt,
    );

    final recordingId = 'rec_${now.millisecondsSinceEpoch}';
    final durationSeconds =
        widget.duration.inSeconds > 0 ? widget.duration.inSeconds : 1;
    final categoryTag = '#$_selectedCategory';
    final autoTranscribe = _preferencesService.autoTranscribeOnSave;

    final initialSnippet = autoTranscribe
        ? 'Transcribing audio on device...'
        : 'Audio saved ($categoryTag). Tap to open player and transcribe.';

    final initialRecording = RecordingSummary(
      id: recordingId,
      title: finalTitle,
      createdAt: now,
      durationSeconds: durationSeconds,
      transcriptSnippet: initialSnippet,
      speakers: const ['Speaker 1'],
      tags: [categoryTag],
      isFavorite: false,
      audioFilePath: savedFilePath,
    );

    final initialPlaceholderSegment = TranscriptSegment(
      id: '${recordingId}_seg_0',
      recordingId: recordingId,
      startMs: 0,
      endMs: durationSeconds * 1000,
      speakerId: 'Speaker 1',
      text: initialSnippet,
    );

    // 2. Insert record into SQLite Recordings table immediately
    await _repository.saveRecordingWithSegments(
      recording: initialRecording,
      segments: [initialPlaceholderSegment],
    );

    // 3. Trigger background worker isolate to run ASR transcription
    if (autoTranscribe) {
      final lang = _preferencesService.primaryLanguage;
      final resolvedLang = lang == 'auto' ? 'en' : lang;
      final modelType = resolvedLang == 'km'
          ? AsrModelType.metaMmsKhmer
          : AsrModelType.moonshineBase;

      final coordinator = widget.transcriptionCoordinator ??
          TranscriptionWorkerCoordinator(repository: _repository);

      final request = TranscriptionWorkerRequest(
        recordingId: recordingId,
        audioFilePath: savedFilePath,
        modelType: modelType,
        language: resolvedLang,
        title: finalTitle,
        tags: [categoryTag],
        fallbackDurationSeconds: durationSeconds,
        createdAtMs: now.millisecondsSinceEpoch,
      );

      // Run asynchronously and dispose coordinator when done if owned locally
      unawaited(
        coordinator
            .transcribe(request: request)
            .then<void>((_) {}, onError: (_) {})
            .whenComplete(() {
          if (widget.transcriptionCoordinator == null) {
            coordinator.dispose();
          }
        }),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      SaveRecordingDialogResult(
        action: SaveRecordingAction.saved,
        recording: initialRecording,
        savedFilePath: savedFilePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final formattedDuration = _formatDurationMmSs(widget.duration);
    final formattedSize = widget.fileSizeBytes > 0
        ? RecordingStorageService.formatBytes(widget.fileSizeBytes)
        : RecordingStorageService.formatBytes(
            (widget.duration.inSeconds > 0 ? widget.duration.inSeconds : 1) *
                32000,
          );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: AppColors.borderDark, width: 1),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bookmark_added_rounded,
                      color: AppColors.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Save & Tag Voice Note',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Organize and index your recording on device',
                          style: TextStyle(
                            color: AppColors.textSecondaryDark,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Title Input Field
              const Text(
                'TITLE',
                style: TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceContainerDark,
                  prefixIcon: const Icon(
                    Icons.edit_note_rounded,
                    color: AppColors.accent,
                  ),
                  hintText: 'Enter recording title...',
                  hintStyle: const TextStyle(color: AppColors.textSecondaryDark),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.borderDark),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.borderDark),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Folder / Category Chip Selector
              const Text(
                'FOLDER / CATEGORY',
                style: TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SaveRecordingDialog.categories.map((category) {
                  final isSelected = _selectedCategory == category;
                  return ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = category;
                        });
                      }
                    },
                    selectedColor: AppColors.accent,
                    backgroundColor: AppColors.surfaceContainerDark,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondaryDark,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.borderDark,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // File Metadata Card (Duration, File Size, Target Directory)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Duration: $formattedDuration',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.sd_storage_outlined,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Size: $formattedSize',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.folder_outlined,
                          size: 16,
                          color: AppColors.textSecondaryDark,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.targetDirectoryPath,
                            style: const TextStyle(
                              color: AppColors.textSecondaryDark,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Action Buttons: Discard & Save & Transcribe
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _handleDiscard,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Discard'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.recording,
                        side: const BorderSide(color: AppColors.recording),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isProcessing ? null : _handleSaveAndTranscribe,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text(
                        'Save & Transcribe',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
