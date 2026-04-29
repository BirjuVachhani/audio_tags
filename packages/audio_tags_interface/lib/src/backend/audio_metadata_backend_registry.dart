import 'audio_metadata_backend.dart';

/// Registry for dynamically registering and creating backends by ID.
final class AudioMetadataBackendRegistry {
  AudioMetadataBackendRegistry._();

  static final instance = AudioMetadataBackendRegistry._();

  final Map<String, AudioMetadataBackend Function()> _factories = {};

  /// Register a backend factory under the given [id].
  void register(String id, AudioMetadataBackend Function() factory) {
    _factories[id] = factory;
  }

  /// Unregister a previously registered backend.
  void unregister(String id) {
    _factories.remove(id);
  }

  /// Whether a backend with the given [id] is registered.
  bool isRegistered(String id) => _factories.containsKey(id);

  /// Create a backend instance by [id].
  ///
  /// Throws [StateError] if no backend is registered for the given [id].
  AudioMetadataBackend create(String id) {
    final factory = _factories[id];
    if (factory == null) {
      throw StateError('No backend registered for "$id"');
    }
    return factory();
  }
}
