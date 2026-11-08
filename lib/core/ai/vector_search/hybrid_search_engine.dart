import 'package:flutter/foundation.dart';
import '../../database/recording_repository.dart';
import 'embedding_generator.dart';
import 'vector_store.dart';

/// Citation reference pointing to a specific spoken segment in a voice note.
@immutable
class CitationChip {
  const CitationChip({
    required this.recordingId,
    required this.recordingTitle,
    required this.speakerId,
    required this.startMs,
    required this.endMs,
    required this.snippet,
  });

  final String recordingId;
  final String recordingTitle;
  final String speakerId;
  final int startMs;
  final int endMs;
  final String snippet;

  String get formattedStartTime => _formatMs(startMs);
  String get formattedEndTime => _formatMs(endMs);
  String get formattedTimeRange => '$formattedStartTime - $formattedEndTime';

  static String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Unified hybrid search result blending keyword BM25/FTS5 and dense vector similarity.
@immutable
class HybridSearchResult {
  const HybridSearchResult({
    required this.recordingId,
    required this.recordingTitle,
    required this.segmentId,
    required this.startMs,
    required this.endMs,
    required this.speakerId,
    required this.text,
    required this.audioFilePath,
    required this.semanticScore,
    required this.keywordScore,
    required this.combinedScore,
  });

  final String recordingId;
  final String recordingTitle;
  final String segmentId;
  final int startMs;
  final int endMs;
  final String speakerId;
  final String text;
  final String audioFilePath;
  final double semanticScore;
  final double keywordScore;
  final double combinedScore;

  String get formattedStartTime => _formatMs(startMs);
  String get formattedEndTime => _formatMs(endMs);
  String get formattedTimeRange => '$formattedStartTime - $formattedEndTime';

  static String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Structured response from the "Ask Your Memory" engine containing
/// synthesized natural language answer and ranked citations.
@immutable
class HybridSearchResponse {
  const HybridSearchResponse({
    required this.query,
    required this.generativeSummary,
    required this.citations,
    required this.results,
  });

  final String query;
  final String generativeSummary;
  final List<CitationChip> citations;
  final List<HybridSearchResult> results;
}

/// Hybrid search engine combining SQLite FTS5 lexical ranking with
/// all-MiniLM-L6-v2 dense vector similarity and generative answer synthesis.
class HybridSearchEngine {
  HybridSearchEngine({
    RecordingRepository? repository,
    VectorStore? vectorStore,
    EmbeddingGenerator? embeddingGenerator,
  })  : _repository = repository ?? RecordingRepository(),
        _vectorStore = vectorStore ?? VectorStore(),
        _embeddingGenerator =
            embeddingGenerator ?? MiniLmL6V2EmbeddingGenerator();

  final RecordingRepository _repository;
  final VectorStore _vectorStore;
  final EmbeddingGenerator _embeddingGenerator;

  /// Executes hybrid retrieval: FTS5 keyword search + Dense Vector k-NN matching.
  Future<HybridSearchResponse> search({
    required String query,
    int limit = 6,
    double semanticWeight = 0.65, // 65% dense vector, 35% lexical keyword
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return const HybridSearchResponse(
        query: '',
        generativeSummary: '',
        citations: [],
        results: [],
      );
    }

    // 1. Lexical Retrieval via SQLite FTS5
    final ftsResult = await _repository.searchFts(cleanQuery);
    final ftsMatches = ftsResult.getOrNull() ?? [];

    // Map FTS5 matches by recordingId for quick lookup
    final ftsScoreMap = <String, double>{};
    for (int i = 0; i < ftsMatches.length; i++) {
      final rankScore = 1.0 - (i / (ftsMatches.length + 1));
      ftsScoreMap[ftsMatches[i].recordingId] = rankScore;
    }

    // 2. Semantic Retrieval via all-MiniLM-L6-v2 Vector Store
    final queryEmbedding = await _embeddingGenerator.generateEmbedding(cleanQuery);
    final vectorMatches = await _vectorStore.search(
      queryEmbedding: queryEmbedding,
      limit: limit * 2,
      minSimilarity: 0.15,
    );

    // 3. Fetch full recording details to assemble unified results
    final recordingsResult = await _repository.getAllRecordings();
    final allRecordings = recordingsResult.getOrNull() ?? [];
    final recordingMap = {for (final r in allRecordings) r.id: r};

    // 4. Hybrid Rank Fusion
    final combinedMap = <String, HybridSearchResult>{};

    for (final vm in vectorMatches) {
      final chunk = vm.chunk;
      final rec = recordingMap[chunk.recordingId];
      final recTitle = rec?.title ?? 'Recorded Conversation';
      final audioPath = rec?.audioFilePath ?? '';

      final kwScore = ftsScoreMap[chunk.recordingId] ?? 0.1;
      final semScore = vm.similarity.clamp(0.0, 1.0);
      final combined = (semanticWeight * semScore) + ((1.0 - semanticWeight) * kwScore);

      combinedMap[chunk.id] = HybridSearchResult(
        recordingId: chunk.recordingId,
        recordingTitle: recTitle,
        segmentId: chunk.segmentId,
        startMs: chunk.startMs,
        endMs: chunk.endMs,
        speakerId: chunk.speakerId,
        text: chunk.chunkText,
        audioFilePath: audioPath,
        semanticScore: semScore,
        keywordScore: kwScore,
        combinedScore: combined,
      );
    }

    // If FTS returned recordings not yet in vector results, incorporate their segments
    for (final fts in ftsMatches) {
      final rec = recordingMap[fts.recordingId];
      if (rec != null) {
        final segmentsResult = await _repository.getSegmentsForRecording(rec.id);
        final segments = segmentsResult.getOrNull() ?? [];

        for (final seg in segments) {
          final chunkId = 'emb_${seg.id}';
          if (!combinedMap.containsKey(chunkId)) {
            final kwScore = ftsScoreMap[rec.id] ?? 0.8;
            const semScore = 0.35; // Default neutral semantic score
            final combined = (semanticWeight * semScore) + ((1.0 - semanticWeight) * kwScore);

            combinedMap[chunkId] = HybridSearchResult(
              recordingId: rec.id,
              recordingTitle: rec.title,
              segmentId: seg.id,
              startMs: seg.startMs,
              endMs: seg.endMs,
              speakerId: seg.speakerId,
              text: seg.text,
              audioFilePath: rec.audioFilePath,
              semanticScore: semScore,
              keywordScore: kwScore,
              combinedScore: combined,
            );
          }
        }
      }
    }

    final sortedResults = combinedMap.values.toList()
      ..sort((a, b) => b.combinedScore.compareTo(a.combinedScore));

    final topResults = sortedResults.take(limit).toList();

    // 5. Synthesize Generative Summary with Clickable Citations
    final citations = <CitationChip>[];
    for (final res in topResults.take(3)) {
      citations.add(
        CitationChip(
          recordingId: res.recordingId,
          recordingTitle: res.recordingTitle,
          speakerId: res.speakerId,
          startMs: res.startMs,
          endMs: res.endMs,
          snippet: res.text,
        ),
      );
    }

    final summary = _synthesizeGenerativeAnswer(cleanQuery, topResults);

    return HybridSearchResponse(
      query: cleanQuery,
      generativeSummary: summary,
      citations: citations,
      results: topResults,
    );
  }

  /// Synthesizes an on-device contextual summary citing exact speaker statements.
  String _synthesizeGenerativeAnswer(String query, List<HybridSearchResult> matches) {
    if (matches.isEmpty) {
      return 'No relevant spoken memories found matching your inquiry. Try rephrasing or searching for related keywords.';
    }

    final top = matches.first;
    final otherSpeakers = matches.map((m) => m.speakerId).toSet().join(', ');

    final buffer = StringBuffer();
    buffer.write('Based on your spoken notes from "${top.recordingTitle}" with $otherSpeakers: ');

    if (matches.length == 1) {
      buffer.write('At ${top.formattedStartTime}, ${top.speakerId} stated: "${top.text}".');
    } else {
      buffer.write('At ${top.formattedStartTime}, ${top.speakerId} noted: "${top.text}" ');
      final second = matches[1];
      buffer.write('Followed at ${second.formattedStartTime} with: "${second.text}".');
    }

    return buffer.toString();
  }
}
