import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'recording_storage_service.dart';

/// Action emitted when the user taps an interactive button on the ongoing Android notification.
enum NotificationRecordingAction {
  pauseResume,
  stopAndSave,
}

/// Metadata written periodically during active recordings for crash/OS-kill recovery.
class CrashRecoveryJournalEntry {
  const CrashRecoveryJournalEntry({
    required this.tempFilePath,
    required this.title,
    required this.startedAtMs,
    required this.elapsedSeconds,
    this.category = 'General',
  });

  final String tempFilePath;
  final String title;
  final int startedAtMs;
  final int elapsedSeconds;
  final String category;

  DateTime get startedAt => DateTime.fromMillisecondsSinceEpoch(startedAtMs);

  Map<String, dynamic> toMap() => {
        'tempFilePath': tempFilePath,
        'title': title,
        'startedAtMs': startedAtMs,
        'elapsedSeconds': elapsedSeconds,
        'category': category,
      };

  factory CrashRecoveryJournalEntry.fromMap(Map<String, dynamic> map) {
    return CrashRecoveryJournalEntry(
      tempFilePath: map['tempFilePath'] as String? ?? '',
      title: map['title'] as String? ?? 'Recovered Voice Note',
      startedAtMs: map['startedAtMs'] as int? ?? 0,
      elapsedSeconds: map['elapsedSeconds'] as int? ?? 1,
      category: map['category'] as String? ?? 'General',
    );
  }
}

/// Service bridging Flutter with the native Android Ongoing Recording Notification,
/// Home Screen Quick Capture Widget, Runtime Permissions, Disk Space Guard,
/// and Crash Recovery Journal.
class RecordingNotificationService {
  RecordingNotificationService({
    MethodChannel? channel,
    String? customRecoveryDirPath,
  })  : _channel = channel ??
            const MethodChannel('com.kinvoice.kinvoice/ambient_service'),
        _customRecoveryDirPath = customRecoveryDirPath {
    _setupMethodCallHandler();
  }

  static final RecordingNotificationService instance =
      RecordingNotificationService();

  final MethodChannel _channel;
  final String? _customRecoveryDirPath;

  final StreamController<NotificationRecordingAction> _actionController =
      StreamController<NotificationRecordingAction>.broadcast();
  final StreamController<bool> _quickRecordController =
      StreamController<bool>.broadcast();

  Stream<NotificationRecordingAction> get actionStream =>
      _actionController.stream;
  Stream<bool> get quickRecordStream => _quickRecordController.stream;

  void _setupMethodCallHandler() {
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onNotificationAction') {
          final raw = call.arguments as String? ?? '';
          if (raw == 'pause_resume') {
            _actionController.add(NotificationRecordingAction.pauseResume);
          } else if (raw == 'stop_and_save') {
            _actionController.add(NotificationRecordingAction.stopAndSave);
          }
        } else if (call.method == 'onQuickRecordLaunch') {
          _quickRecordController.add(true);
        }
      });
    } catch (_) {}
  }

  /// Formats a [Duration] as `HH:MM:SS` for the ongoing notification timer.
  static String formatDurationHhMmSs(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// Starts the ongoing Android foreground recording notification.
  Future<void> startRecordingNotification({
    required String title,
    Duration elapsed = Duration.zero,
    bool isPaused = false,
  }) async {
    try {
      await _channel.invokeMethod('startAmbientService', {
        'notificationTitle': title,
        'notificationText': isPaused ? 'Recording paused' : 'Recording audio...',
        'elapsed': formatDurationHhMmSs(elapsed),
        'isPaused': isPaused,
      });
    } catch (_) {}
  }

  /// Updates the live elapsed `HH:MM:SS` timer and Pause/Resume state in the ongoing notification.
  Future<void> updateRecordingNotification({
    required String title,
    required Duration elapsed,
    required bool isPaused,
  }) async {
    try {
      await _channel.invokeMethod('updateRecordingNotification', {
        'notificationTitle': title,
        'notificationText': isPaused ? 'Recording paused' : 'Recording audio...',
        'elapsed': formatDurationHhMmSs(elapsed),
        'isPaused': isPaused,
      });
    } catch (_) {}
  }

  /// Stops and removes the ongoing recording notification.
  Future<void> stopRecordingNotification() async {
    try {
      await _channel.invokeMethod('stopAmbientService');
    } catch (_) {}
  }

  /// Checks if the app was launched via the 1-Tap Home Screen Quick Record Widget.
  Future<bool> consumeQuickRecordLaunchIntent() async {
    try {
      final res =
          await _channel.invokeMethod<bool>('consumeQuickRecordIntent');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if a pending notification action (`stop_and_save` / `pause_resume`) woke the activity.
  Future<NotificationRecordingAction?> consumePendingNotificationAction() async {
    try {
      final res =
          await _channel.invokeMethod<String>('consumeNotificationAction');
      if (res == 'stop_and_save') {
        return NotificationRecordingAction.stopAndSave;
      } else if (res == 'pause_resume') {
        return NotificationRecordingAction.pauseResume;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Requests `RECORD_AUDIO`, `POST_NOTIFICATIONS`, and `FOREGROUND_SERVICE_MICROPHONE`.
  Future<bool> requestAllPermissions() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestAllPermissions');
      return granted ?? true;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the OS application settings screen when permissions are permanently denied.
  Future<bool> openAppSettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openAppSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Queries available free disk bytes on device storage.
  /// Defaults to 1 GB in test environments without native channel.
  Future<int> getFreeDiskBytes() async {
    try {
      final bytes = await _channel.invokeMethod<int>('getFreeDiskBytes');
      return bytes ?? (1024 * 1024 * 1024);
    } catch (_) {
      return 1024 * 1024 * 1024;
    }
  }

  /// Minimum free disk space required to start or continue recording (15 MB).
  static const int minRequiredFreeBytes = 15 * 1024 * 1024;

  /// Returns true if the device has sufficient free storage space for audio recording.
  Future<bool> hasSufficientStorage({int? simulatedAvailableBytes}) async {
    final available = simulatedAvailableBytes ?? await getFreeDiskBytes();
    return available >= minRequiredFreeBytes;
  }

  // ---------------------------------------------------------------------------
  // Crash & OS-Kill Recovery Journal
  // ---------------------------------------------------------------------------

  Future<File> _getJournalFile() async {
    if (_customRecoveryDirPath != null) {
      final dir = Directory(_customRecoveryDirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}${Platform.pathSeparator}recovery_journal.json');
    }
    final tempDir =
        await RecordingStorageService.instance.getTempRecordingDirectory();
    return File(
      '${tempDir.path}${Platform.pathSeparator}recovery_journal.json',
    );
  }

  /// Writes or updates the active recording recovery journal on disk so unfinalized
  /// audio can be recovered if the OS terminates the app due to low memory.
  Future<void> writeRecoveryJournal(CrashRecoveryJournalEntry entry) async {
    try {
      final file = await _getJournalFile();
      await file.writeAsString(jsonEncode(entry.toMap()), flush: true);
    } catch (_) {}
  }

  /// Clears the recovery journal upon normal recording save or discard.
  Future<void> clearRecoveryJournal() async {
    try {
      final file = await _getJournalFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Checks if an unfinalized recording exists from a previous OS kill or crash.
  Future<CrashRecoveryJournalEntry?> checkUnfinalizedRecording() async {
    try {
      final file = await _getJournalFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final map = jsonDecode(content) as Map<String, dynamic>;
      final entry = CrashRecoveryJournalEntry.fromMap(map);
      final audioFile = File(entry.tempFilePath);
      if (await audioFile.exists() && await audioFile.length() > 44) {
        return entry;
      }
      await clearRecoveryJournal();
      return null;
    } catch (_) {
      return null;
    }
  }
}
