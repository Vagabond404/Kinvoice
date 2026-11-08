import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/recording_repository.dart';

/// Summary metadata returned upon completion of a 1-click backup.
@immutable
class BackupExportResult {
  const BackupExportResult({
    required this.jsonPath,
    required this.zipPath,
    required this.recordingsCount,
    required this.segmentsCount,
    required this.fileSizeBytes,
    required this.exportedAt,
  });

  final String jsonPath;
  final String zipPath;
  final int recordingsCount;
  final int segmentsCount;
  final int fileSizeBytes;
  final DateTime exportedAt;

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// Service handling 1-click JSON and ZIP export backups of all local
/// recordings, metadata, and spoken transcript segments.
class BackupExportService {
  BackupExportService({
    RecordingRepository? repository,
    String? initialOutputDirectoryPath,
  })  : _repository = repository ?? RecordingRepository(),
        _outputDirectoryPath = initialOutputDirectoryPath;

  final RecordingRepository _repository;
  final String? _outputDirectoryPath;

  /// Executes full 1-click export generating both JSON and ZIP archives.
  Future<BackupExportResult> exportAllData() async {
    final now = DateTime.now();
    final timestampStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    final exportDir = await _resolveExportDirectory();
    final jsonFile = File(p.join(exportDir.path, 'kinvoice_backup_$timestampStr.json'));
    final zipFile = File(p.join(exportDir.path, 'kinvoice_backup_$timestampStr.zip'));

    final recordingsResult = await _repository.getAllRecordings();
    final recordings = recordingsResult.getOrNull() ?? [];

    int totalSegments = 0;
    final List<Map<String, dynamic>> exportedRecordings = [];

    final archive = Archive();

    for (final rec in recordings) {
      final segmentsResult = await _repository.getSegmentsForRecording(rec.id);
      final segments = segmentsResult.getOrNull() ?? [];
      totalSegments += segments.length;

      exportedRecordings.add({
        'id': rec.id,
        'title': rec.title,
        'created_at': rec.createdAt.toIso8601String(),
        'duration_seconds': rec.durationSeconds,
        'audio_file_path': rec.audioFilePath,
        'is_favorite': rec.isFavorite,
        'transcript_snippet': rec.transcriptSnippet,
        'tags': rec.tags,
        'speakers': rec.speakers,
        'segments': segments.map((s) => s.toMap()).toList(),
      });

      // If local audio file exists, embed inside the zip
      final audioFile = File(rec.audioFilePath);
      if (await audioFile.exists()) {
        try {
          final audioBytes = await audioFile.readAsBytes();
          final audioName = p.basename(rec.audioFilePath);
          archive.addFile(
            ArchiveFile(
              'audio/$audioName',
              audioBytes.length,
              audioBytes,
            ),
          );
        } catch (_) {}
      }
    }

    final Map<String, dynamic> rootPayload = {
      'app': 'Kinvoice',
      'version': '1.0.0',
      'exported_at': now.toIso8601String(),
      'recordings_count': recordings.length,
      'total_segments_count': totalSegments,
      'recordings': exportedRecordings,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(rootPayload);
    await jsonFile.writeAsString(jsonString);

    // Add JSON manifest to ZIP archive
    final jsonBytes = utf8.encode(jsonString);
    archive.addFile(
      ArchiveFile(
        'manifest.json',
        jsonBytes.length,
        jsonBytes,
      ),
    );

    // Encode ZIP archive
    final zipEncoder = ZipEncoder();
    final encodedZip = zipEncoder.encode(archive);
    await zipFile.writeAsBytes(encodedZip);

    final fileSize = await zipFile.exists() ? await zipFile.length() : jsonBytes.length;

    return BackupExportResult(
      jsonPath: jsonFile.path,
      zipPath: zipFile.path,
      recordingsCount: recordings.length,
      segmentsCount: totalSegments,
      fileSizeBytes: fileSize,
      exportedAt: now,
    );
  }

  Future<Directory> _resolveExportDirectory() async {
    if (_outputDirectoryPath != null) {
      final dir = Directory(_outputDirectoryPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(docsDir.path, 'kinvoice_exports'));
    if (!await exportDir.exists()) {
      await dirCreate(exportDir);
    }
    return exportDir;
  }

  Future<void> dirCreate(Directory dir) async {
    await dir.create(recursive: true);
  }
}
