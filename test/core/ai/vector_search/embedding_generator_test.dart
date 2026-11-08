import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ai/vector_search/embedding_generator.dart';

void main() {
  group('MiniLmL6V2EmbeddingGenerator Unit Tests', () {
    late MiniLmL6V2EmbeddingGenerator generator;

    setUp(() {
      generator = MiniLmL6V2EmbeddingGenerator();
    });

    tearDown(() {
      generator.dispose();
    });

    test('Initializes with 384-dimensional specifications', () {
      expect(generator.embeddingDimension, 384);
      expect(generator.isInitialized, isFalse);
    });

    test('Generates 384-dim unit-normalized vector with L2 norm = 1.0', () async {
      await generator.initialize();
      expect(generator.isInitialized, isTrue);

      final emb = await generator.generateEmbedding('Q3 strategic marketing plan');
      expect(emb.length, 384);

      double sumSq = 0.0;
      for (int i = 0; i < 384; i++) {
        sumSq += emb[i] * emb[i];
      }
      expect((sumSq - 1.0).abs(), lessThan(1e-4));
    });

    test('Cosine similarity between identical embeddings is 1.0', () async {
      final embA = await generator.generateEmbedding('sprint sync backlog review');
      final embB = await generator.generateEmbedding('sprint sync backlog review');

      final sim = MiniLmL6V2EmbeddingGenerator.computeCosineSimilarity(embA, embB);
      expect((sim - 1.0).abs(), lessThan(1e-4));
    });

    test('Semantically related phrases produce elevated cosine similarity', () async {
      final embMarketing1 =
          await generator.generateEmbedding('marketing campaign budget decision');
      final embMarketing2 =
          await generator.generateEmbedding('advertising market finance costs');
      final embUnrelated =
          await generator.generateEmbedding('karusak martial arts training dojo');

      final relatedSim = MiniLmL6V2EmbeddingGenerator.computeCosineSimilarity(
        embMarketing1,
        embMarketing2,
      );
      final unrelatedSim = MiniLmL6V2EmbeddingGenerator.computeCosineSimilarity(
        embMarketing1,
        embUnrelated,
      );

      expect(relatedSim, greaterThan(0.65));
      expect(unrelatedSim, lessThan(0.40));
    });

    test('Batch embedding generation accurately processes multiple texts', () async {
      final texts = [
        'Voice memo on strategy',
        'Action items from Karusak',
        'Dinner with mom on the weekend',
      ];

      final embeddings = await generator.generateBatchEmbeddings(texts);
      expect(embeddings.length, 3);
      for (final e in embeddings) {
        expect(e.length, 384);
      }
    });
  });
}
