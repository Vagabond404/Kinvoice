import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Service managing local file storage for Kinvoice recordings,
/// enforcing `[ApplicationDocumentsDirectory]/Kinvoice/Recordings/` organization
/// and `Kinvoice_[Category]_[Timestamp].[format]` naming conventions.
class RecordingStorageService {
  RecordingStorageService({this.customBaseDirectoryPath});

  static final RecordingStorageService instance = RecordingStorageService();

  final String? customBaseDirectoryPath;

  /// Resolves and creates `[ApplicationDocumentsDirectory]/Kinvoice/Recordings/`.
  Future<Directory> getRecordingsDirectory() async {
    String basePath;
    if (customBaseDirectoryPath != null) {
      basePath = customBaseDirectoryPath!;
    } else {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        basePath = docsDir.path;
      } catch (_) {
        basePath = Directory.systemTemp.path;
      }
    }

    final recordingsDir = Directory(p.join(basePath, 'Kinvoice', 'Recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    return recordingsDir;
  }

  /// Resolves and creates a temporary staging directory for active recording capture.
  Future<Directory> getTempRecordingDirectory() async {
    String basePath;
    if (customBaseDirectoryPath != null) {
      basePath = customBaseDirectoryPath!;
    } else {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        basePath = docsDir.path;
      } catch (_) {
        basePath = Directory.systemTemp.path;
      }
    }

    final tempDir = Directory(p.join(basePath, 'Kinvoice', 'Temp'));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }

  /// Returns the absolute path string to `[ApplicationDocumentsDirectory]/Kinvoice/Recordings/`.
  Future<String> getRecordingsDirectoryPath() async {
    final dir = await getRecordingsDirectory();
    return dir.path;
  }

  /// Generates a standardized filename: `Kinvoice_[Category]_[Timestamp].[format]`.
  String generateFileName({
    required String category,
    required DateTime timestamp,
    String formatExtension = 'wav',
  }) {
    final cleanCategory = category
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')
        .isEmpty
        ? 'General'
        : category.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final cleanExt = formatExtension.replaceAll('.', '').toLowerCase();
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    final tsString = '$y$m${d}_$hh$mm${ss}_$ms';

    return 'Kinvoice_${cleanCategory}_$tsString.$cleanExt';
  }

  /// Moves a temporary recording file into `[ApplicationDocumentsDirectory]/Kinvoice/Recordings/`
  /// following the `Kinvoice_[Category]_[Timestamp].[format]` naming convention.
  Future<String> persistRecordingFile({
    required String tempFilePath,
    required String category,
    DateTime? timestamp,
    String? formatExtension,
  }) async {
    final targetDir = await getRecordingsDirectory();
    final ext = formatExtension ??
        (p.extension(tempFilePath).isNotEmpty
            ? p.extension(tempFilePath).substring(1)
            : 'wav');
    final fileName = generateFileName(
      category: category,
      timestamp: timestamp ?? DateTime.now(),
      formatExtension: ext,
    );
    final destinationPath = p.join(targetDir.path, fileName);

    final sourceFile = File(tempFilePath);
    if (await sourceFile.exists()) {
      try {
        await sourceFile.rename(destinationPath);
      } on FileSystemException {
        await sourceFile.copy(destinationPath);
        await sourceFile.delete();
      }
      return destinationPath;
    }

    return destinationPath;
  }

  /// Deletes an audio file from local storage if it exists.
  Future<void> deleteAudioFile(String filePath) async {
    if (filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Returns the size in bytes of the file at [filePath], or 0 if not found.
  Future<int> getFileSizeBytes(String filePath) async {
    if (filePath.isEmpty) return 0;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Formats a byte count into a human-readable string (e.g., `428.5 KB` or `1.4 MB`).
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }

  /// Shares an audio file or exported text file via the system share sheet (`share_plus`).
  Future<void> shareAudioFile({
    required String filePath,
    String? title,
  }) async {
    final file = File(filePath);
    if (await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          subject: title ?? 'Kinvoice Voice Recording',
        ),
      );
    } else if (title != null && title.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          text: '$title ($filePath)',
        ),
      );
    }
  }

  /// Shares plain text content (such as transcripts or SRT exports) via the system share sheet.
  Future<void> shareTextContent({
    required String text,
    String? subject,
  }) async {
    if (text.trim().isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
      ),
    );
  }

  /// Shares both the audio file (.wav / .m4a) AND the formatted transcript text together
  /// via the native share sheet (WhatsApp, Telegram, Gmail, etc.).
  Future<void> shareAudioAndTranscript({
    required String filePath,
    required String transcriptText,
    String? title,
  }) async {
    final file = File(filePath);
    final subject = title ?? 'Kinvoice Voice Note & Transcript';
    if (await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: transcriptText.trim().isEmpty ? subject : transcriptText,
          subject: subject,
        ),
      );
    } else {
      await shareTextContent(
        text: transcriptText.trim().isEmpty
            ? '$subject ($filePath)'
            : transcriptText,
        subject: subject,
      );
    }
  }

  /// Writes an exported subtitle (.srt) or transcript (.txt) file into the Kinvoice
  /// recordings directory and returns the saved file path.
  Future<String> saveExportedTranscriptFile({
    required String title,
    required String extension,
    required String content,
  }) async {
    final dir = await getRecordingsDirectory();
    final safeTitle = title
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final cleanTitle = safeTitle.isEmpty ? 'Transcript' : safeTitle;
    final cleanExt = extension.replaceAll('.', '').toLowerCase();
    final filePath = p.join(dir.path, '${cleanTitle}_export.$cleanExt');
    final file = File(filePath);
    await file.writeAsString(content);
    return filePath;
  }

  /// Deletes all saved audio files and temporary recordings inside `Kinvoice/`.
  Future<void> clearAllRecordingsAndCache() async {
    try {
      final recDir = await getRecordingsDirectory();
      if (await recDir.exists()) {
        await for (final entity in recDir.list(recursive: true)) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      final tempDir = await getTempRecordingDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: true)) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }
}
