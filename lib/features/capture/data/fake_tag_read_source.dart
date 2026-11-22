import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/canonical_json.dart';
import '../application/ports.dart';
import '../domain/tag_observation.dart';

abstract interface class ReaderSeqStore {
  Future<int> nextReaderSeq();
}

/// Software stand-in for the handheld reader (no hardware/SDK confirmed yet, DONGA-01).
/// Emits TagObservation v1 reads, MOBILE kind. It verifies the software contract only –
/// not range, interference, frequency or physical timing.
class FakeTagReadSource implements TagReadSource {
  FakeTagReadSource({required this.readerId, required this.seqStore, Clock? clock})
      : _clock = clock ?? DateTime.now;

  final String readerId;
  final ReaderSeqStore seqStore;
  final Clock _clock;
  final _controller = StreamController<TagObservation>.broadcast();
  static const _uuid = Uuid();

  @override
  Stream<TagObservation> get observations => _controller.stream;

  /// Several tag IDs in one call = several tags in the antenna field at once.
  Future<void> emit(List<String> tagIds) async {
    for (final tag in tagIds) {
      final seq = await seqStore.nextReaderSeq();
      _controller.add(TagObservation(
        observationId: _uuid.v4(),
        readerId: readerId,
        seq: seq,
        tagId: tag,
        observedAt: _clock(),
      ));
    }
  }

  Future<void> dispose() => _controller.close();
}
